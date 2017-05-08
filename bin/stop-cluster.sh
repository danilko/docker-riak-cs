#! /bin/bash

set -e

eval $(minikube docker-env -u)
kubectl delete -f ../kubernetes/riak-cs.yaml
kubectl delete -f ../kubernetes/traefik.yaml
