output "cluster_name" {
  description = "EKS cluster name."
  value       = module.eks.cluster_name
}

output "aws_region" {
  description = "AWS Region used by the deployment."
  value       = var.aws_region
}

output "cluster_endpoint" {
  description = "EKS API endpoint."
  value       = module.eks.cluster_endpoint
}

output "configure_kubectl" {
  description = "Command that configures kubectl for the cluster."
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks.cluster_name}"
}

output "private_subnet_ids" {
  description = "Private subnets discovered by Karpenter."
  value       = module.vpc.private_subnets
}
