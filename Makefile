SHELL := /bin/bash
CLUSTER ?= ticketflow-local
APP_DIR ?= ../ticketflow-engine
IMAGE ?= ticketflow:local

.PHONY: cluster-up cluster-down build-image load-image deploy status logs observability load-test chaos-pod chaos-pool chaos-redis
cluster-up:
	kind create cluster --name $(CLUSTER) --config kind.yaml
cluster-down:
	kind delete cluster --name $(CLUSTER)
build-image:
	docker build -t $(IMAGE) $(APP_DIR)
load-image:
	kind load docker-image $(IMAGE) --name $(CLUSTER)
deploy:
	kubectl apply -k k8s/overlays/local
status:
	kubectl get all,pdb,hpa -n ticketflow
	kubectl get events -n ticketflow --sort-by=.lastTimestamp
logs:
	kubectl logs -n ticketflow deploy/ticketflow --all-containers=true --tail=200 -f
observability:
	helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
	helm repo update
	helm upgrade --install monitoring prometheus-community/kube-prometheus-stack --version 69.8.2 --namespace monitoring --create-namespace -f observability/kube-prometheus-stack-values.yaml
load-test:
	k6 run load/booking.js
chaos-pod:
	chaos/delete-one-pod.sh
chaos-pool:
	chaos/saturate-db-pool.sh
chaos-redis:
	chaos/redis-unavailable.sh
