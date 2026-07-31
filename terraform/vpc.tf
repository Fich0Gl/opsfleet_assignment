module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.0"

  name = "${var.cluster_name}-vpc"
  cidr = var.vpc_cidr

  azs = local.availability_zones

  private_subnets = [
    for index, az in local.availability_zones : cidrsubnet(var.vpc_cidr, 4, index)
  ]

  public_subnets = [
    for index, az in local.availability_zones : cidrsubnet(var.vpc_cidr, 8, index + 48)
  ]

  intra_subnets = [
    for index, az in local.availability_zones : cidrsubnet(var.vpc_cidr, 8, index + 52)
  ]

  enable_nat_gateway = true
  single_nat_gateway = var.single_nat_gateway

  enable_dns_hostnames = true
  enable_dns_support   = true

  public_subnet_tags = {
    "kubernetes.io/role/elb" = "1"
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = "1"
    "karpenter.sh/discovery"          = var.cluster_name
  }

  tags = local.tags
}
