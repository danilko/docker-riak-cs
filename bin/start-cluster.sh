#! /bin/bash

set -e

docker build -t "danilko/riak-cs" .
kubectl apply -f ../kubernetes/traefik.yaml
kubectl apply -f ../kubernetes/riak-cs.yaml

# DNS name
echo "$(minikube ip) traefik-ui.local" | sudo tee -a /etc/hosts
echo "$(minikube ip) riak.local" | sudo tee -a /etc/hosts

echo "curl -H \"Host: s3.amazonaws.com\" http://$(minikube ip)/riak-cs/ping"
echo "curl -H \"Host: raik-bucket.amazonaws.com\" http://$(minikube ip)/riak-cs/ping"
echo "curl -H \"Host: riak.local\" http://$(minikube ip)/riak-cs/ping"
echo "curl -H \"Host: traefik-ui.local\" http://$(minikube ip)"

echo "Shell Access: kubectl exec --namespace riak-cs-namespace -it $(kubectl get pods --namespace riak-cs-namespace | grep riak | cut -d ' ' -f1) -- bin/bash"
echo "Pod Access: kubectl get pods --namespace riak-cs-namespace"

echo "Access Key Id: $kubectl get secrets riak-cs-admin-credential -o json --namespace riak-cs-namespace | grep RIAK_CS_ADMIN_KEY | cut -d '"' -f4 | base64 -d)"
echo "Access Secret: kubectl get secrets riak-cs-admin-credential -o json --namespace riak-cs-namespace | grep RIAK_CS_ADMIN_SECRET | cut -d '"' -f4 | base64 -d)"
