variable "aws_region" {
  description = "AWS Region in which the POC is deployed."
  type        = string
  default     = "eu-central-1"
}

variable "cluster_name" {
  description = "Name of the EKS cluster and prefix for related resources."
  type        = string
  default     = "opsfleet-karpenter-poc"

  validation {
    condition     = can(regex("^[0-9A-Za-z][0-9A-Za-z_-]{0,29}$", var.cluster_name))
    error_message = "cluster_name must start with an alphanumeric character, contain only alphanumeric characters, underscores, or hyphens, and be no more than 30 characters."
  }
}

variable "kubernetes_version" {
  description = "EKS Kubernetes minor version."
  type        = string
  default     = "1.36"
}

variable "cluster_endpoint_public_access" {
  description = "Enable the public EKS Kubernetes API endpoint."
  type        = bool
  default     = true
}

variable "vpc_cidr" {
  description = "CIDR block for the dedicated VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "Explicit Availability Zones to use. When empty, zones are discovered automatically."
  type        = list(string)
  default     = []

  validation {
    condition = (
      length(var.availability_zones) == 0 ||
      length(distinct(var.availability_zones)) >= 2
    )

    error_message = "availability_zones must be empty or contain at least two distinct Availability Zones."
  }

  validation {
    condition = (
      length(var.availability_zones) ==
      length(distinct(var.availability_zones))
    )

    error_message = "availability_zones must not contain duplicate Availability Zones."
  }
}

variable "availability_zone_count" {
  description = "Number of Availability Zones used by the VPC."
  type        = number
  default     = 3

  validation {
    condition     = var.availability_zone_count >= 2
    error_message = "At least two Availability Zones must be selected."
  }
}

variable "single_nat_gateway" {
  description = "Use one NAT Gateway for the POC. Set false for one NAT Gateway per AZ."
  type        = bool
  default     = true
}

variable "cluster_endpoint_public_access_cidrs" {
  description = "CIDRs allowed to reach the public EKS API endpoint. Restrict this to trusted /32 addresses."
  type        = list(string)

  validation {
    condition     = length(var.cluster_endpoint_public_access_cidrs) > 0 && !contains(var.cluster_endpoint_public_access_cidrs, "0.0.0.0/0")
    error_message = "Provide at least one trusted CIDR and do not expose the EKS API endpoint to 0.0.0.0/0."
  }
}

variable "system_node_instance_types" {
  description = "Instance types for the small managed node group that hosts Karpenter and system pods."
  type        = list(string)
  default     = ["m6i.large"]
}

variable "system_node_min_size" {
  description = "Minimum size of the system managed node group."
  type        = number
  default     = 2
}

variable "system_node_desired_size" {
  description = "Desired size of the system managed node group."
  type        = number
  default     = 2
}

variable "system_node_max_size" {
  description = "Maximum size of the system managed node group."
  type        = number
  default     = 3
}

variable "tags" {
  description = "Additional tags applied to AWS resources."
  type        = map(string)
  default     = {}
}
