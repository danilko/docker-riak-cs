#! /bin/bash

set -e

curl -s -H "Host: riak.local" "http://$(minikube ip)/stats"| python -mjson.tool
