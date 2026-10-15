variable "project_id" {
  type = string
}
variable "network_id" {
  type = string
}
variable "image_id" {
  type        = string
  description = "Existing Hammerspace 5.2.14-1267 image with uefi=false."
}
variable "security_group_ids" {
  type = list(string)
  validation {
    condition     = length(var.security_group_ids) > 0
    error_message = "Supply existing security groups permitting required management/cluster traffic."
  }
}
variable "region" {
  type    = string
  default = "eu01"
}
variable "availability_zone" {
  type    = string
  default = "eu01-3"
}
variable "name" {
  type    = string
  default = "hs-poc-anvil"
}
variable "machine_type" {
  type    = string
  default = "g1a.16d"
}
variable "ipv4" {
  type        = string
  default     = null
  description = "Optional free address in the existing STACKIT network; otherwise STACKIT assigns it."
}
variable "config_revision" {
  type        = string
  default     = "1"
  description = "Per-deployment identifier used in the config image name; do not change after bootstrap."
}
