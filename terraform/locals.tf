locals {
  available_availability_zones = sort(data.aws_availability_zones.available.names)

  automatically_selected_availability_zones = slice(local.available_availability_zones, 0, var.availability_zone_count)

  availability_zones = length(var.availability_zones) > 0 ? (var.availability_zones) : (local.automatically_selected_availability_zones)

  amazon_ssm_managed_instance_core_policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"

  tags = merge(
    {
      Project     = "OpsFleet DevOps Assessment"
      Environment = "poc"
      ManagedBy   = "Terraform"
    },
    var.tags,
  )
}
