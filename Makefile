.PHONY: all build start-cluster test-cluster stop-cluster

all: stop-cluster riak-cs-container start-cluster

riak-cs-container:
	eval $(minikube docker-env) && docker build -t "danilko/riak-cs" .

start-cluster:
	. bin/start-cluster.sh

test-cluster:
	. bin/test-cluster.sh

stop-cluster:
	. bin/stop-cluster.sh
