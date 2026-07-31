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
