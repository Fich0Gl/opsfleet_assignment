terraform {
  backend "s3" {
    bucket       = "karpenter-poc-terraform-state"
    key          = "eks-karpenter/terraform.tfstate"
    region       = "eu-central-1"
    encrypt      = true
    use_lockfile = true
  }
}
