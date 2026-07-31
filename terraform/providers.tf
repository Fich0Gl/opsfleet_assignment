provider "aws" {
  region = var.aws_region

  default_tags {
    tags = local.tags
  }
}

data "aws_availability_zones" "available" {
  state = "available"

  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }

  lifecycle {
    postcondition {
      condition = alltrue([
        for az in var.availability_zones :
        contains(self.names, az)
      ])

      error_message = format(
        "The following Availability Zones are not available in the selected AWS Region: %s.",
        join(
          ", ",
          tolist(
            setsubtract(
              toset(var.availability_zones),
              toset(self.names)
            )
          )
        )
      )
    }

    postcondition {
      condition = (
        length(var.availability_zones) > 0 ||
        length(self.names) >= var.availability_zone_count
      )

      error_message = format(
        "availability_zone_count requests %d zones, but only %d matching zones are available.",
        var.availability_zone_count,
        length(self.names)
      )
    }
  }
}
