module "karpenter" {
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "21.24.0"

  cluster_name = module.eks.cluster_name

  enable_inline_policy = true

  create_pod_identity_association = true
  create_node_iam_role            = true
  create_access_entry             = true
  enable_spot_termination         = true

  # Gives the role a predictable name.
  node_iam_role_use_name_prefix = false
  node_iam_role_name            = "${var.cluster_name}-karpenter-node"

  node_iam_role_additional_policies = {
    AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  }

  tags = local.tags
}

resource "aws_iam_service_linked_role" "ec2_spot" {
  count            = var.create_ec2_spot_service_linked_role ? 1 : 0
  aws_service_name = "spot.amazonaws.com"
  description      = "Allows Amazon EC2 Spot to launch and manage Spot Instances."
}

resource "helm_release" "karpenter" {
  name             = "karpenter"
  namespace        = "kube-system"
  create_namespace = false

  repository = "oci://public.ecr.aws/karpenter"
  chart      = "karpenter"
  version    = var.karpenter_version

  atomic          = true
  cleanup_on_fail = true
  wait            = true
  timeout         = 900

  values = [
    yamlencode({
      nodeSelector = {
        "karpenter.sh/controller" = "true"
      }

      dnsPolicy = "Default"

      controller = {
        resources = {
          requests = {
            cpu    = "1"
            memory = "1Gi"
          }
          limits = {
            cpu    = "1"
            memory = "1Gi"
          }
        }
      }

      settings = {
        clusterName       = module.eks.cluster_name
        interruptionQueue = module.karpenter.queue_name
        clusterEndpoint   = module.eks.cluster_endpoint
        enableZonalShift  = true
      }
    })
  ]

  depends_on = [
    module.eks,
    module.karpenter,
    aws_iam_service_linked_role.ec2_spot
  ]
}

resource "helm_release" "karpenter_config" {
  name      = "karpenter-config"
  namespace = "kube-system"
  chart     = "${path.module}/charts/karpenter-config"

  atomic          = true
  cleanup_on_fail = true
  wait            = true
  timeout         = 1200

  values = [
    yamlencode({
      clusterName  = var.cluster_name
      nodeRoleName = module.karpenter.node_iam_role_name
      amiAlias     = var.karpenter_ami_alias

      limits = {
        cpu    = var.karpenter_nodepool_cpu_limit
        memory = var.karpenter_nodepool_memory_limit
      }
    })
  ]

  depends_on = [helm_release.karpenter]
}
