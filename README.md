# kubernetes-riak-cs
This is a [Kubernetes](https://kubernetes.io) project to bring up a local [Riak CS](https://github.com/basho/riak_cs) cluster in Kubernetes

This is based on Docker work by [hectcastro](https://github.com/hectcastro/docker-riak-cs)

### Main Objectives

* Use [Kubernetes](https://kubernetes.io) for orchestration
* Eliminate SSH needs, credentials are stored in [Kubernetes secrets](https://kubernetes.io/docs/concepts/configuration/secret/) and can be accessed through Kubernetes API. This [article](http://danilko.blogspot.com/2017/04/kubernetes-share-config-setting.html) explains how this is achieved through Kubernetes API and [Kubernetes RBAC Authorization](https://kubernetes.io/docs/admin/authorization/rbac/)
* Use one central [Træfik](https://github.com/containous/traefik) reverse proxy for all external connections and elimiate need to do custom port binding or forwarding once done
* Utilize Kubernetes [Livenessprobe and Readinessprobe](https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-probes/) to monitor the container by default

### TO DO Items
* Internal cluster join


## Prerequisites

### Install Docker

Follow the [instructions on Docker's website](https://www.docker.io/gettingstarted/#h_installation) to install Docker

Follow the [instructions on Kubernetes' website](https://kubernetes.io/docs/tutorials/stateless-application/hello-minikube/) to install MiniKube

Follow the s3curl [instruction on s3curl's website](https://aws.amazon.com/code/128) for testing with instruction at [here](https://github.com/basho/riak_cs/wiki/Using-s3curl)

### Launch cluster

```bash
$       minikube start --vm-driver=kvm --extra-config=apiserver.Authorization.Mode=RBAC
$       eval $(minikube docker-env)

$       # Speical setting for Fedora 25
$       if [ -z "$(cat /etc/sysconfig/docker | grep '/etc/docker/certs')" ]; then echo "DOCKER_CERT_PATH=/etc/docker/certs" | sudo tee -a /etc/sysconfig/docker; fi
$       sudo cp -rf ~/.minikube/certs /etc/docker/
$       sudo chmod a+r -R /etc/docker/certs

$       # Create volume to persistent data after container stop 
$       # Need to setup the volume permission correctly on the node (https://github.com/kubernetes/kubernetes/issues/31269)
$       minikube ssh 'mkdir -p /tmp/data; chmod a+rwt /tmp/data; chcon -Rt svirt_sandbox_file_t /tmp/data;'
$       # Note: If the instance/cluster has problem or want new cluster, please delete the temp data
$       # minikube ssh 'rm -rf /tmp/data; mkdir -p /tmp/data; chmod a+rwt /tmp/data; chcon -Rt svirt_sandbox_file_t /tmp/data'

$       docker build -t "danilko/riak-cs" .
$       kubectl apply -f kubernetes/traefik.yaml
$       kubectl apply -f kubernetes/riak-cs.yaml

$       # DNS name
$       echo "$(minikube ip) traefik-ui.local" | sudo tee -a /etc/hosts
$       echo "$(minikube ip) s3.amazonaws.local" | sudo tee -a /etc/hosts
$       echo "$(minikube ip) riak.local" | sudo tee -a /etc/hosts

$       make start-cluster
```

## Readiness/Liveness

The deployment is integrated with readiness and liveness hook to check if the container is ready to serve up traffic

One can see the stats at [http://traefik-ui.local/dashboard/#/](http://traefik-ui.local/dashboard/#/)

The current configuration is to utilize
`/riak-cs/ping`
as health check

## Replication

Cluster size is controlled by replication controller within the Kubernetes deployment

It is currently set to 1

```
apiVersion: apps/v1beta1
kind: Deployment
metadata: 
  name: riak-cs-deployment
  namespace: riak-cs-namespace
spec: 
  replicas: 1
  template: 
    metadata: 
      labels: 
        app: riak-cs-deployment
```


## Testing

From outside the container, we can interact with the HTTP interfaces of Riak and Riak CS. Additionally, the Riak CS HTTP interface supports an [Amazon S3](http://docs.basho.com/riakcs/latest/references/apis/storage/s3/) or [OpenStack Swift](http://docs.basho.com/riakcs/latest/references/apis/storage/openstack/) compatible API.

### Riak HTTP

Riak's HTTP interface has an endpoint called `/stats` that emits Riak
statistics. The current cluster setup will allow to reach 8090 endpoint through DNS `raik.local`

The most interesting attributes for testing cluster membership are
`ring_members`:

```bash
$ make test-cluster | egrep -A6 "ring_members"
"ring_members": [
        "riak@172.17.0.4"
    ],
```

And `ring_ownership`:

```bash
$ make test-cluster | egrep "ring_ownership"
    "ring_ownership": "[{'riak@172.17.0.4',64}]",
```

Together, these attributes let us know that this particular Riak node knows
about all of the other Riak instances.

### Amazon S3

`s3curl` is convenient command-line tool to test the Riak CS Amazon S3 compatible API.

One can get Riak-CS credential in Kubernetes Secret (it is created during the deployment)
```bash
$ kubectl get secrets riak-cs-admin-credential -o json --namespace riak-cs-namespace | grep RIAK_CS_ADMIN_KEY | cut -d '"' -f4 | base64 -d
$ kubectl get secrets riak-cs-admin-credential -o json --namespace riak-cs-namespace | grep RIAK_CS_ADMIN_SECRET | cut -d '"' -f4 | base64 -d
```

The credential will be available as `RIAK_CS_ADMIN_KEY` and `RIAK_CS_ADMIN_SECRET`

```bash
J4O8EZ1_R7QRTKSPZBEP
WkD9S9NfWJuy7oPBRpZZLhUWOOWVTLaZ01YFLQ==
```

Now we have everything needed to connect to the cluster with `s3curl`:

Configure s3curl

```bash
$ cat > ~/.s3curl <<EOL
 %awsSecretAccessKeys = (
     admin => {
         id => 'ACCESS_ID',
         key => 'ACCESS_SECRET',
     },
 );
EOL

$ # Replace with correct setting
$ sed -i 's/ACCESS_ID/'$(kubectl get secrets riak-cs-admin-credential -o json --namespace riak-cs-namespace | grep RIAK_CS_ADMIN_KEY | cut -d '"' -f4 | base64 -d)'/g' ~/.s3curl
$ sed -i 's/ACCESS_SECRET/'$(kubectl get secrets riak-cs-admin-credential -o json --namespace riak-cs-namespace | grep RIAK_CS_ADMIN_SECRET | cut -d '"' -f4 | base64 -d)'/g' ~/.s3curl

$ chmod 600 ~/.s3curl

```

#### List bucket
```bash
$ ./s3curl.pl --id admin -- -s -v -x $(minikube ip):80 http://s3.amazonaws.com/
*   Trying 192.168.42.139...
* TCP_NODELAY set
* Connected to s3.amazonaws.com (192.168.42.139) port 80 (#0)
> GET http://s3.amazonaws.com/ HTTP/1.1
> Host: s3.amazonaws.com
> User-Agent: curl/7.51.0
> Accept: */*
> Proxy-Connection: Keep-Alive
> Date: Mon, 08 May 2017 02:09:35 +0000
> Authorization: AWS LI8ZKXZKGJNCJKOQOW0S:Q9iac3iA7ZrE3zr5uSvfyRNG8x0=
> 
< HTTP/1.1 200 OK
< Content-Length: 265
< Content-Type: application/xml
< Date: Mon, 08 May 2017 02:09:34 GMT
< Server: Riak CS
< 
* Curl_http_done: called premature == 0
* Connection #0 to host s3.amazonaws.com left intact
<?xml version="1.0" encoding="UTF-8"?><ListAllMyBucketsResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/"><Owner><ID>6fd61d8b4aadedb0b28cdc508e35f3f91a3729bea38eee573c1e49b9005eb102</ID><DisplayName>admin</DisplayName></Owner><Buckets/></ListAllMyBucketsResult>[danilko@localhost s3-curl]$ 
[danilko@localhost s3-curl]$ ./s3curl.pl --id admin -- -s -v -x $(minikube ip):80 http://s3.amazonaws.com/
*   Trying 192.168.42.139...
* TCP_NODELAY set
* Connected to 192.168.42.139 (192.168.42.139) port 80 (#0)
> GET http://s3.amazonaws.com/ HTTP/1.1
> Host: s3.amazonaws.com
> User-Agent: curl/7.51.0
> Accept: */*
> Proxy-Connection: Keep-Alive
> Date: Mon, 08 May 2017 02:20:46 +0000
> Authorization: AWS TDXTSW-Z4QCIPQQDSA6C:uANTYxHCh+EoH6PR2EWsiuofD8I=
> 
< HTTP/1.1 200 OK
< Content-Length: 265
< Content-Type: application/xml
< Date: Mon, 08 May 2017 02:20:45 GMT
< Server: Riak CS
< 
* Curl_http_done: called premature == 0
* Connection #0 to host 192.168.42.139 left intact
<?xml version="1.0" encoding="UTF-8"?><ListAllMyBucketsResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/"><Owner><ID>03684036d84c63f6cff86e225bd5fe75555188baf57e5f86c133f47e20ae3319</ID><DisplayName>admin</DisplayName></Owner><Buckets/></ListAllMyBucketsResult>
```

#### Create new bucket

This particular Raik-CS deployment handle the bucket creation at the reverse proxy [Træfik](https://github.com/containous/traefik) through three setting:

```
spec:
  rules:
  - host: '*.s3.amazonaws.com'
    http:
      paths:
      - backend:
          serviceName: riak-cs-service
          servicePort: 8080
  - host: 's3.amazonaws.com'
    http:
      paths:
      - backend:
          serviceName: riak-cs-service
          servicePort: 8080
  - host: 'riak-cs.local'
    http:
      paths:
      - backend:
          serviceName: riak-cs-service
          servicePort: 8080
  - host: riak.local
    http:
      paths:
      - backend:
          serviceName: riak-cs-service
          servicePort: 8098
```

The first rule `*.s3.amazonaws.com` will handle new bucket creation such as `new-bucket.s3.amazonaws.com` as the new bucket creation will require a host header pass in with `<bucket-name>.s3.amazon.aws.com` (will need to stay as is for the deployment to work with S3 API)
The second rule `s3.amazonaws.com` will handle normal operation against `s3.amazonaws.com` such as list object, if the api is hitting through `s3.amazonaws.com/<bucket-name>` instead of `<bucket-name>.s3.amazon.aws.com` (will need to stay as is for the deployment to work with S3 API)
The third rule `riak-cs.local` will handle normal request to `RAIK-CS` API (this can be changed as needed)
The forth rule `riak.local` will handle normal request to backend `RAIK` API (this can be changed as needed)

One can then use the `s3curl` command to create the s3 bucket `new-bucket.s3.amazonaws.com`
```bash
$ ./s3curl.pl --id=admin --createBucket -- -x $(minikube ip):80 http://s3.amazonaws.com/new-bucket
*   Trying 192.168.42.139...
* TCP_NODELAY set
* Connected to 192.168.42.139 (192.168.42.139) port 80 (#0)
> PUT http://new-bucket.s3.amazonaws.com/ HTTP/1.1
> Host: new-bucket.s3.amazonaws.com
> User-Agent: curl/7.51.0
> Accept: */*
> Proxy-Connection: Keep-Alive
> Date: Mon, 08 May 2017 02:28:34 +0000
> Authorization: AWS TDXTSW-Z4QCIPQQDSA6C:Ny8TcGeeaI+9uomQ9bbYNd4RwpE=
> 
< HTTP/1.1 200 OK
< Content-Length: 0
< Content-Type: application/xml
< Date: Mon, 08 May 2017 02:28:33 GMT
< Server: Riak CS
< 
* Curl_http_done: called premature == 0
* Connection #0 to host 192.168.42.139 left intact
```

#### Upload File
```bash

$ # Create dummyfile for testing file upload
$ echo "dummy file s3 test" > dummyfile

$ # Check the file is not there
$ ./s3curl.pl --id admin -- -x $(minikube ip):80 "http://s3.amazonaws.com/new-bucket/dummyfile" -s
<?xml version="1.0" encoding="UTF-8"?><Error><Code>NoSuchKey</Code><Message>The specified key does not exist.</Message><Resource>/new-bucket/dummyfile</Resource><RequestId></RequestId></Error>

$ ./s3curl.pl --id admin --put=dummyfile -- -s -v -x $(minikube ip):80 http://s3.amazonaws.com/new-bucket/dummyfile
*   Trying 192.168.42.139...
* TCP_NODELAY set
* Connected to 192.168.42.139 (192.168.42.139) port 80 (#0)
> PUT http://s3.amazonaws.com/new-bucket/dummyfile HTTP/1.1
> Host: s3.amazonaws.com
> User-Agent: curl/7.51.0
> Accept: */*
> Proxy-Connection: Keep-Alive
> Date: Mon, 08 May 2017 03:25:32 +0000
> Authorization: AWS YURYTLYZPELOLOOKGKCC:BsFKNzJNW0wd7ewXcycQNAX7gEo=
> Content-Length: 13
> Expect: 100-continue
> 
< HTTP/1.1 100 Continue
* We are completely uploaded and fine
< HTTP/1.1 200 OK
< Content-Length: 0
< Content-Type: text/plain
< Date: Mon, 08 May 2017 03:25:32 GMT
< Etag: "6e28ff42c9c601cd163c53152392b8a3"
< Server: Riak CS
< 
* Curl_http_done: called premature == 0
* Connection #0 to host 192.168.42.139 left intact

$ # Get the content of the file
$ ./s3curl.pl --id admin -- -x $(minikube ip):80 "http://s3.amazonaws.com/new-bucket/dummyfile" -s
dummys3 test

$ # Get the metedata
./s3curl.pl --id admin --head -- -x $(minikube ip):80 "http://s3.amazonaws.com/new-bucket/dummyfile" -s
HTTP/1.1 200 OK
Content-Length: 13
Content-Type: application/octet-stream
Date: Mon, 08 May 2017 03:26:25 GMT
Etag: "6e28ff42c9c601cd163c53152392b8a3"
Last-Modified: Mon, 08 May 2017 03:25:32 GMT
Server: Riak CS

$ # Delete the file
$ ./s3curl.pl --id admin --delete -- -x $(minikube ip):80 "http://s3.amazonaws.com/new-bucket/dummyfile" -s

$ # Confirm File no longer exist
$ ./s3curl.pl --id admin -- -x $(minikube ip):80 "http://s3.amazonaws.com/new-bucket/dummyfile" -s
<?xml version="1.0" encoding="UTF-8"?><Error><Code>NoSuchKey</Code><Message>The specified key does not exist.</Message><Resource>/new-bucket/dummyfile</Resource><RequestId></RequestId></Error>
```

### SSH 

```bash
$ kubectl exec --namespace riak-cs-namespace -it $(kubectl get pods --namespace riak-cs-namespace | grep riak | cut -d ' ' -f1) -- bin/bash
```

## Destroying

```bash
$ make stop-cluster
./bin/stop-cluster.sh
```
