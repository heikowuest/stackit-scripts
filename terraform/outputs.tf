output "network" {
  value = {
    role    = "anvil"
    ip      = stackit_network_interface.anvil.ipv4
    prefix  = data.stackit_network.existing.ipv4_prefix_length
    gateway = data.stackit_network.existing.ipv4_gateway
    dns     = data.stackit_network.existing.ipv4_nameservers
  }
}
output "bootstrap" {
  value = {
    role              = "anvil"
    project_id        = var.project_id
    region            = var.region
    name              = var.name
    machine_type      = var.machine_type
    availability_zone = var.availability_zone
    nic_id            = stackit_network_interface.anvil.network_interface_id
    boot_id           = stackit_volume.boot.volume_id
    metadata_id       = stackit_volume.metadata.volume_id
    config_id         = stackit_volume.config.volume_id
  }
}
output "management_url" {
  value = "https://${stackit_network_interface.anvil.ipv4}:8443"
}
output "server_id" {
  value = stackit_server.anvil.server_id
}
