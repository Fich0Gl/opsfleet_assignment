# AWS EKS with Karpenter, Graviton, and Spot

This directory contains a Terraform proof of concept that creates an Amazon EKS cluster in a dedicated VPC and installs Karpenter for dynamic `amd64` and `arm64` worker capacity.

The solution demonstrates:

- Amazon EKS running the latest supported Kubernetes version selected for this assignment
- A dedicated multi-AZ VPC
- A small on-demand EKS managed node group for cluster-critical components
- Karpenter installed with EKS Pod Identity
- Separate Karpenter NodePools for x86 and AWS Graviton workloads
- Spot and on-demand capacity support
- Native interruption handling through Amazon EventBridge and Amazon SQS
- Example Deployments that trigger x86 or Graviton Spot capacity

> This is a proof of concept. The [Production considerations](#production-considerations) section describes changes recommended before using the design for production workloads.

## Version selection

The following versions were selected and tested for this assignment:

| Component | Version |
|---|---:|
| Kubernetes on EKS | `1.36` |
| Karpenter | `1.14.0` |
| `terraform-aws-eks` module | `21.24.0` |
| Terraform AWS provider | `~> 6.52` |
| Terraform Helm provider | `~> 3.2` |

At the time of implementation, Kubernetes `1.36` was the latest version available in EKS standard support. Karpenter `1.14.0` supports Kubernetes `1.36`.

Versions are intentionally explicit so upgrades can be tested rather than applied automatically.

## Architecture

```text
                              AWS account
┌──────────────────────────────────────────────────────────────────────┐
│                                                                      │
│  EKS public API endpoint                 EKS private API endpoint    │
│  restricted to trusted CIDRs             available inside the VPC    │
│                                                                      │
│  Dedicated VPC across 2 or 3 Availability Zones                      │
│                                                                      │
│  ┌──────────────────────┐                                            │
│  │ Public subnets       │                                            │
│  │ - Internet Gateway   │                                            │
│  │ - NAT Gateway(s)     │                                            │
│  │ - Public LBs         │                                            │
│  └──────────┬───────────┘                                            │
│             │ outbound egress                                        │
│  ┌──────────▼────────────────────────────────────────────────────┐   │
│  │ Private subnets                                               │   │
│  │                                                               │   │
│  │  EKS managed system node group                                │   │
│  │  - CoreDNS                                                    │   │
│  │  - VPC CNI                                                    │   │
│  │  - kube-proxy                                                 │   │
│  │  - EKS Pod Identity Agent                                     │   │
│  │  - Karpenter controller                                       │   │
│  │                                                               │   │
│  │  Karpenter-managed workload nodes                             │   │
│  │  - amd64: Spot or on-demand                                   │   │
│  │  - arm64/Graviton: Spot or on-demand                          │   │
│  └───────────────────────────────────────────────────────────────┘   │
│                                                                      │
│  ┌──────────────────────┐                                            │
│  │ Intra subnets        │                                            │
│  │ - EKS cross-account  │                                            │
│  │   network interfaces │                                            │
│  │ - No internet route  │                                            │
│  └──────────────────────┘                                            │
│                                                                      │
│  AWS interruption events                                             │
│       └── EventBridge ──► encrypted SQS queue ──► Karpenter          │
│                                                                      │
└──────────────────────────────────────────────────────────────────────┘
```

The intra subnets host the EKS cross-account network interfaces used for communication between the AWS-managed control plane and resources in the VPC.

Karpenter runs on the managed system node group rather than on capacity that it manages itself. This avoids a bootstrap and recovery dependency in which the autoscaler would need to provision the node required to run its own controller.

## Repository layout

```text
terraform/
├── charts/
│   └── karpenter-config/
│       ├── Chart.yaml
│       ├── values.yaml
│       └── templates/
│           ├── ec2nodeclass.yaml
│           ├── nodepool-amd64.yaml
│           └── nodepool-arm64.yaml
├── examples/
│   ├── amd64-deployment.yaml
│   └── arm64-deployment.yaml
├── backend.tf.example
├── eks.tf
├── karpenter.tf
├── locals.tf
├── Makefile
├── outputs.tf
├── providers.tf
├── README.md
├── terraform.tfvars
├── terraform.tfvars.example
├── variables.tf
├── versions.tf
└── vpc.tf
```

## Prerequisites

Install:

- [Terraform](http://developer.hashicorp.com/terraform/install) `1.10` or newer
- [AWS CLI v2](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)
- [`kubectl`](https://kubernetes.io/docs/tasks/tools/) compatible with Kubernetes `1.36`
- GNU Make, optionally

The AWS identity running Terraform must be able to create and manage:

- VPC, subnet, route table, NAT Gateway, Elastic IP, and security-group resources
- EKS clusters, managed node groups, add-ons, access entries, and Pod Identity associations
- IAM roles, policies, instance profiles, and required service-linked roles
- SQS queues and EventBridge rules
- CloudWatch log groups and the EKS encryption key created by the EKS module
- Objects in the configured Terraform state bucket, when the S3 backend is enabled

For an isolated assessment account, a temporary administrator execution role is the simplest bootstrap option. A production setup should use a dedicated, least-privilege Terraform execution role.

Verify the active identity:

```bash
aws sts get-caller-identity
```

## EC2 Spot service-linked role

EC2 Spot uses the account-level role:

```text
AWSServiceRoleForEC2Spot
```

Check whether it already exists:

```bash
aws iam get-role --role-name AWSServiceRoleForEC2Spot
```

If it exists, leave this value as `false`:

```hcl
create_ec2_spot_service_linked_role = false
```

For a new account where the role does not exist, set:

```hcl
create_ec2_spot_service_linked_role = true
```

## Configure the deployment

From the repository root:

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
```

At minimum, replace the example EKS API CIDR with the public IP of the workstation:

```hcl
cluster_endpoint_public_access_cidrs = [
  "YOUR.PUBLIC.IP/32"
]
```

Find the current public IPv4 address, for example:

```bash
curl -4 https://checkip.amazonaws.com
```

The public EKS API endpoint is enabled for POC reproducibility but restricted to the configured CIDRs. Private endpoint access is also enabled.

The example configuration uses:

```hcl
aws_region                  = "eu-central-1"
availability_zone_count     = 3
single_nat_gateway          = true
system_node_instance_types  = ["t3.medium"]
```
A single NAT Gateway reduces POC cost but introduces a shared zonal dependency. See [Production considerations](#production-considerations).
> [!IMPORTANT]
> The committed `terraform.tfvars` file is included intentionally to demonstrate the configuration values used while testing this proof of concept. It does not contain credentials or other sensitive values.

## Optional S3 backend

Terraform uses local state when no backend configuration is present.

For shared or persistent usage, create a globally unique S3 bucket:

```bash
export TF_STATE_BUCKET="replace-with-a-globally-unique-bucket-name"
export AWS_REGION="eu-central-1"

aws s3api create-bucket \
  --bucket "${TF_STATE_BUCKET}" \
  --region "${AWS_REGION}" \
  --create-bucket-configuration "LocationConstraint=${AWS_REGION}"

aws s3api put-bucket-versioning \
  --bucket "${TF_STATE_BUCKET}" \
  --versioning-configuration Status=Enabled

aws s3api put-public-access-block \
  --bucket "${TF_STATE_BUCKET}" \
  --public-access-block-configuration \
'{
  "BlockPublicAcls": true,
  "IgnorePublicAcls": true,
  "BlockPublicPolicy": true,
  "RestrictPublicBuckets": true
}'
```

Copy and edit the backend example:

```bash
cp backend.tf.example backend.tf
```

Example backend:

```hcl
terraform {
  backend "s3" {
    bucket       = "replace-with-a-globally-unique-bucket-name"
    key          = "eks-karpenter/terraform.tfstate"
    region       = "eu-central-1"
    encrypt      = true
    use_lockfile = true
  }
}
```

`use_lockfile = true` enables Terraform's native S3 state locking. S3 Versioning provides recovery of previous state versions.  
> [!IMPORTANT]
> The committed `backend.tf` file is included intentionally as an example of the S3 backend configuration used during testing. The configured bucket is environment-specific and must be replaced with a bucket accessible from your AWS account before running `terraform init`.

## Deploy

Using Terraform directly:

```bash
terraform fmt -recursive
terraform init
terraform validate
terraform plan -out=tfplan
terraform apply tfplan
```

Equivalent Make targets:

```bash
make fmt
make init
make validate
make plan
make apply
```

The initial deployment creates:

- The VPC and subnets
- The EKS control plane
- Two on-demand managed system nodes
- EKS add-ons
- Karpenter's AWS-side IAM and interruption resources
- The Karpenter controller
- The `EC2NodeClass`
- The `amd64` and `arm64` NodePools

Karpenter workload nodes are not created until Kubernetes has a compatible unschedulable Pod.

## Configure kubectl

```bash
aws eks update-kubeconfig \
  --region "$(terraform output -raw aws_region)" \
  --name "$(terraform output -raw cluster_name)"
```

Or:

```bash
make kubeconfig
```

Verify the deployment:

```bash
kubectl get nodes \
  -L kubernetes.io/arch,karpenter.sh/capacity-type,karpenter.sh/nodepool

kubectl get pods -n kube-system
kubectl get ec2nodeclasses
kubectl get nodepools
kubectl get nodeclaims
```

The two initial nodes should belong to the EKS managed system node group. Karpenter-created nodes appear only after one of the example workloads is applied.

## Test x86 Spot capacity

Apply the x86 example:

```bash
kubectl apply -f examples/amd64-deployment.yaml
```

Or:

```bash
make test-amd64
```

Watch the Pod, NodeClaim, and node:

```bash
kubectl get pods -l app=workload-amd64 -o wide --watch
kubectl get nodeclaims --watch
```

The workload uses:

```yaml
nodeSelector:
  workload.opsfleet.io/architecture: amd64
  karpenter.sh/capacity-type: spot
```

The custom architecture label prevents the workload from using the existing x86 managed system nodes. The `amd64` NodePool also constrains `kubernetes.io/arch` to `amd64`.

Inspect the resulting node:

```bash
kubectl get nodes \
  -L kubernetes.io/arch,karpenter.sh/capacity-type,karpenter.sh/nodepool,node.kubernetes.io/instance-type
```

## Test Graviton Spot capacity

The container image used by an Arm workload must support `linux/arm64`.

Apply the example:

```bash
kubectl apply -f examples/arm64-deployment.yaml
```

Or:

```bash
make test-arm64
```

Watch the result:

```bash
kubectl get pods -l app=workload-arm64 -o wide --watch
kubectl get nodeclaims --watch
```

The workload uses:

```yaml
nodeSelector:
  workload.opsfleet.io/architecture: arm64
  karpenter.sh/capacity-type: spot
```

The `arm64` NodePool constrains `kubernetes.io/arch` to `arm64`, causing Karpenter to select a compatible AWS Graviton instance.

## Spot versus on-demand behavior

Both NodePools permit:

```yaml
values:
  - spot
  - on-demand
```

The examples explicitly request Spot to demonstrate the assignment requirement.

To permit Karpenter to select either capacity type, remove this selector from the workload:

```yaml
karpenter.sh/capacity-type: spot
```

## Observe Karpenter

Follow controller logs:

```bash
kubectl logs \
  --namespace kube-system \
  --selector app.kubernetes.io/name=karpenter \
  --container controller \
  --follow
```

Inspect resource status:

```bash
kubectl describe ec2nodeclass default
kubectl describe nodepool amd64
kubectl describe nodepool arm64
kubectl get nodeclaims
```

## Node access

The managed system-node role and Karpenter node role include `AmazonSSMManagedInstanceCore`. EKS-optimized Amazon Linux 2023 images include the SSM Agent.

Nodes are deployed without public IP addresses and without an SSH key. Use AWS Systems Manager Session Manager for troubleshooting:

```bash
aws ssm start-session --target i-0123456789abcdef0
```

The private subnets currently reach Systems Manager through the NAT Gateway. A production environment can replace this dependency with Systems Manager interface VPC endpoints.

## Cleanup

Delete example workloads first:

```bash
kubectl delete \
  --filename examples/amd64-deployment.yaml \
  --ignore-not-found

kubectl delete \
  --filename examples/arm64-deployment.yaml \
  --ignore-not-found
```

Watch Karpenter consolidate the empty workload nodes:

```bash
kubectl get nodeclaims --watch
```

After the Karpenter NodeClaims are gone:

```bash
terraform destroy
```

Or:

```bash
make destroy
```

## Design decisions

### Managed system capacity

Two on-demand x86 managed nodes run Karpenter and cluster-critical add-ons. This keeps the autoscaler independent from the capacity that it controls.

### Separate architecture NodePools

Mutually exclusive NodePools make developer scheduling explicit and demonstrate both x86 and Graviton provisioning.

### Broad instance flexibility

The NodePools constrain architecture, operating system, instance generation, and broad instance categories rather than pinning one instance type. This gives Karpenter more capacity options, which is particularly useful for Spot.

### Spot interruption handling

The Karpenter Terraform submodule creates an SQS interruption queue and EventBridge rules. Karpenter can react to Spot interruption warnings, rebalance recommendations, instance-state changes, AWS Health events, and related capacity events.

### Subnet discovery

Private subnets and the shared node security group are tagged with:

```text
karpenter.sh/discovery = <cluster-name>
```

The `EC2NodeClass` uses this tag to discover eligible networking resources. The tag does not grant Kubernetes or IAM authorization.

## Production considerations

Before adopting this architecture for production:

- **Remote state:** Use a dedicated, versioned, encrypted state bucket with restricted IAM access and native S3 locking.
- **API exposure:** Disable the public EKS endpoint and run Terraform and `kubectl` from a VPN, connected network, bastion, or in-VPC CI runner.
- **NAT resilience:** Use one NAT Gateway per Availability Zone, or evaluate centralized egress and VPC endpoints.
- **System isolation:** Taint the managed system nodes and add the required tolerations to cluster-critical workloads.
- **AMI lifecycle:** Replace `al2023@latest` with a tested, pinned AMI alias and define a controlled rollout process.
- **NodePool guardrails:** Size aggregate CPU and memory limits using workload forecasts and constrain eligible instance sizes where necessary.
- **IAM:** Replace broad bootstrap permissions with a dedicated Terraform execution role, scoped `iam:PassRole`, permissions boundaries, and resource/tag conditions.
- **SSM connectivity:** Add VPC endpoints for Systems Manager in environments without NAT or public AWS API access.
- **Observability:** Add metrics, centralized logs, dashboards, and alerts for EKS and Karpenter.
- **Storage and ingress:** Add the EBS CSI driver and AWS Load Balancer Controller when required by workloads.
- **Backups:** Define backup and disaster-recovery procedures for cluster state and persistent application data.

## References

- [Amazon EKS Kubernetes versions](https://docs.aws.amazon.com/eks/latest/userguide/kubernetes-versions.html)
- [Karpenter getting started](https://karpenter.sh/docs/getting-started/getting-started-with-karpenter/)
- [Karpenter compatibility matrix](https://karpenter.sh/docs/upgrading/compatibility/)
- [Karpenter NodePools](https://karpenter.sh/docs/concepts/nodepools/)
- [Karpenter EC2NodeClass](https://karpenter.sh/docs/concepts/nodeclasses/)
- [Karpenter disruption](https://karpenter.sh/docs/concepts/disruption/)
- [Terraform S3 backend](https://developer.hashicorp.com/terraform/language/backend/s3)
