SHELL := /bin/bash

.PHONY: fmt init validate plan apply kubeconfig test-amd64 test-arm64 nodes destroy

fmt:
	terraform fmt -recursive

init:
	terraform init

validate:
	terraform validate

plan:
	terraform plan -out=tfplan

apply:
	terraform apply tfplan

kubeconfig:
	aws eks update-kubeconfig --region "$$(terraform output -raw aws_region)" --name "$$(terraform output -raw cluster_name)"

test-amd64:
	kubectl apply -f examples/amd64-deployment.yaml

test-arm64:
	kubectl apply -f examples/arm64-deployment.yaml

nodes:
	kubectl get nodes

destroy:
	terraform destroy
