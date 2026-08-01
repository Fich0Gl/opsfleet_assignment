module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "21.24.0"

  name               = var.cluster_name
  kubernetes_version = var.kubernetes_version

  enable_cluster_creator_admin_permissions = true
  authentication_mode                      = "API_AND_CONFIG_MAP"

  endpoint_private_access      = true
  endpoint_public_access       = var.cluster_endpoint_public_access
  endpoint_public_access_cidrs = var.cluster_endpoint_public_access_cidrs

  enabled_log_types = [
    "api",
    "audit",
    "authenticator",
    "controllerManager",
    "scheduler",
  ]

  cloudwatch_log_group_retention_in_days = 7

  upgrade_policy = {
    support_type = "STANDARD"
  }

  zonal_shift_config = {
    enabled = true
  }

  addons = {
    coredns = {}

    eks-pod-identity-agent = {
      before_compute = true
    }

    kube-proxy = {}

    vpc-cni = {
      before_compute = true
    }
  }

  vpc_id                   = module.vpc.vpc_id
  subnet_ids               = module.vpc.private_subnets
  control_plane_subnet_ids = module.vpc.intra_subnets

  eks_managed_node_groups = {
    system = {
      ami_type       = "AL2023_x86_64_STANDARD"
      instance_types = var.system_node_instance_types
      capacity_type  = "ON_DEMAND"

      min_size     = var.system_node_min_size
      desired_size = var.system_node_desired_size
      max_size     = var.system_node_max_size

      labels = {
        "karpenter.sh/controller" = "true"
        "node-role"               = "system"
      }

      update_config = {
        max_unavailable_percentage = 50
      }

      iam_role_additional_policies = {
        AmazonSSMManagedInstanceCore = local.amazon_ssm_managed_instance_core_policy_arn
      }
    }
  }

  node_security_group_tags = {
    "karpenter.sh/discovery" = var.cluster_name
  }

  tags = local.tags
}
