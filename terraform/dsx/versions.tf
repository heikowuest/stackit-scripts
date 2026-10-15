terraform {
  required_version = ">= 1.6.0"
  required_providers {
    stackit = {
      source  = "stackitcloud/stackit"
      version = "= 0.120.0"
    }
  }
}
provider "stackit" {
  default_region = var.region
}
