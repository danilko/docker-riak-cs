#! /bin/bash

set -e
# set -x

# Skip events we don't care about
if [ "${SERF_EVENT}" != "member-join" ] && [ "${SERF_SELF_NAME}" = "riak-cs01" ]; then
  echo "Not a valid event for this node."
  exit 0
fi


# Have the admin credentials been created yet?
if egrep -q "admin-key" /etc/riak-cs/app.config; then
  # Wait for the Riak CS HTTP interface to come up
  until curl -s "http://127.0.0.1:8080/riak-cs/ping" | egrep "OK" > /dev/null;
  do
    sleep 5
  done

  # Create admin credentials
  curl -v --retry 5 --retry-delay 5 -XPOST "http://127.0.0.1:8080/riak-cs/user" \
       -H "Content-Type: application/json" \
       --data '{"email":"admin@admin.com", "name":"admin"}' > /tmp/riak-cs-credentials

  RIAK_CS_ADMIN_KEY=$(egrep -o "\{.*\}" /tmp/riak-cs-credentials | python3 -mjson.tool | egrep "key_id" | cut -d'"' -f4)
  RIAK_CS_ADMIN_SECRET=$(egrep -o "\{.*\}" /tmp/riak-cs-credentials  | python3 -mjson.tool | egrep "key_secret" | cut -d'"' -f4)

  # Kubernetes Config to populate ADMIN credential to secret
  if [ -z "${RIAK_CS_ADMIN_KEY}" ];
  then
    OUTPUT=$(curl -X GET -H "Content-Type:application/json" -H "Authorization: Bearer $(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" -k https://${KUBERNETES_PORT_443_TCP_ADDR}/api/v1/namespaces/$(cat /var/run/secrets/kubernetes.io/serviceaccount/namespace)/secrets/riak-cs-admin-credential | python3 -mjson.tool)

    RIAK_CS_ADMIN_KEY=$(cat $OUTPUT | python3 -mjson.tool | egrep "RIAK_CS_ADMIN_KEY" | cut -d'"' -f4 )
    RIAK_CS_ADMIN_SECRET=$(cat $OUTPUT | python3 -mjson.tool | egrep "RIAK_CS_ADMIN_SECRET" | cut -d'"' -f4 )
  fi


  # Populate admin credentials locally
  sudo su -c "sed -i 's/admin-key/${RIAK_CS_ADMIN_KEY}/' /etc/riak-cs/app.config" - root
  sudo su -c "sed -i 's/admin-secret/${RIAK_CS_ADMIN_SECRET}/' /etc/riak-cs/app.config" - root
  sudo su -c "sed -i 's/{anonymous_user_creation, true},/{anonymous_user_creation, false},/' /etc/riak-cs/app.config" - root
  sudo su -c "sed -i 's/admin-key/${RIAK_CS_ADMIN_KEY}/' /etc/stanchion/app.config" - root
  sudo su -c "sed -i 's/admin-secret/${RIAK_CS_ADMIN_SECRET}/' /etc/stanchion/app.config" - root

  # Restart Riak CS and Stanchion for credentials to take effect
  sudo sv restart riak-cs
  sudo sv restart stanchion

  # Post the secret into secret API
  curl -X POST -H "Content-Type:application/json" -H "Authorization: Bearer $(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" -k https://${KUBERNETES_PORT_443_TCP_ADDR}/api/v1/namespaces/$(cat /var/run/secrets/kubernetes.io/serviceaccount/namespace)/secrets -d "{\"apiVersion\":\"v1\",\"data\":{\"RIAK_CS_ADMIN_KEY\":\"$(echo ${RIAK_CS_ADMIN_KEY} | base64)\",\"RIAK_CS_ADMIN_SECRET\":\"$(echo ${RIAK_CS_ADMIN_SECRET} | base64)\"},\"kind\":\"Secret\",\"metadata\":{\"name\":\"riak-cs-admin-credential\"}}"

  rm /tmp/riak-cs-credentials
else
  RIAK_CS_ADMIN_KEY=$(egrep "admin_key" /etc/riak-cs/app.config | cut -d'"' -f2)
  RIAK_CS_ADMIN_SECRET=$(egrep "admin_secret" /etc/riak-cs/app.config | cut -d'"' -f2)
fi

# Broadcast admin credentials
serf event riak-cs-admin-key "${RIAK_CS_ADMIN_KEY}"
serf event riak-cs-admin-secret "${RIAK_CS_ADMIN_SECRET}"
