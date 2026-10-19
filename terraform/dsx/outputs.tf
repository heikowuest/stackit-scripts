output "network" {
  value = {
    role     = "dsx"
    ip       = stackit_network_interface.dsx.ipv4
    prefix   = data.stackit_network.existing.ipv4_prefix_length
    gateway  = data.stackit_network.existing.ipv4_gateway
    dns      = data.stackit_network.existing.ipv4_nameservers
    anvil_ip = var.anvil_ip
  }
}
output "bootstrap" {
  value = {
    role              = "dsx"
    project_id        = var.project_id
    region            = var.region
    name              = var.name
    machine_type      = var.machine_type
    availability_zone = var.availability_zone
    nic_id            = stackit_network_interface.dsx.network_interface_id
    boot_id           = stackit_volume.boot.volume_id
    metadata_id       = null
    config_id         = try(stackit_volume.config[0].volume_id, null)
  }
}
output "management_url" {
  value = "https://${var.anvil_ip}:8443"
}
output "server_id" {
  value = stackit_server.dsx.server_id
}

output "dsx_ip" {
  value = stackit_network_interface.dsx.ipv4
}

output "data_volume_id" {
  value = try(stackit_volume.data[0].volume_id, null)
}
