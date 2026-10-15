data "stackit_network" "existing" {
  project_id = var.project_id
  network_id = var.network_id
}
resource "stackit_network_interface" "dsx" {
  project_id         = var.project_id
  network_id         = data.stackit_network.existing.network_id
  name               = "${var.name}-nic"
  ipv4               = var.ipv4
  security           = true
  security_group_ids = var.security_group_ids
}
resource "stackit_image" "config" {
  project_id      = var.project_id
  name            = "${var.name}-config-${var.config_revision}"
  disk_format     = "qcow2"
  local_file_path = "${path.module}/.generated/config.qcow2"
  min_disk_size   = 1
  lifecycle {
    precondition {
      condition     = fileexists("${path.module}/.generated/ready")
      error_message = "Generate the real config disk with bootstrap.py prepare before uploading."
    }
  }
}
resource "stackit_volume" "boot" {
  project_id        = var.project_id
  name              = "${var.name}-boot"
  availability_zone = var.availability_zone
  size              = 200
  performance_class = "storage_premium_perf1"
  source = {
    type = "image"
    id   = var.image_id
  }
}
resource "stackit_volume" "data" {
  project_id        = var.project_id
  name              = "${var.name}-data"
  availability_zone = var.availability_zone
  size              = var.data_volume_size
  performance_class = var.data_performance_class
}
resource "stackit_volume" "config" {
  project_id        = var.project_id
  name              = "${var.name}-config"
  availability_zone = var.availability_zone
  size              = 1
  performance_class = "storage_premium_perf1"
  source = {
    type = "image"
    id   = stackit_image.config.image_id
  }
}
# First creation is performed by bootstrap.py with ALL disks in the create
# request, then imported here. Do not run an untargeted apply before import.
resource "stackit_server" "dsx" {
  project_id        = var.project_id
  name              = var.name
  availability_zone = var.availability_zone
  machine_type      = var.machine_type
  network_interfaces = [
    stackit_network_interface.dsx.network_interface_id
  ]
  boot_volume = {
    source_type = "volume"
    source_id   = stackit_volume.boot.volume_id
  }
  agent = {
    provisioning_policy = "NEVER"
  }
  lifecycle {
    prevent_destroy = true
    # Import cannot reconstruct the original boot source or agent policy.
    # Provider 0.120.0 also drops imported NIC IDs when no prior list exists.
    # Bootstrap sets these explicitly; verify actual attachments via STACKIT.
    # NIC and boot volume resources remain managed independently.
    ignore_changes = [
      boot_volume,
      network_interfaces,
      agent.provisioning_policy,
    ]
  }
}
resource "stackit_server_volume_attach" "config" {
  project_id = var.project_id
  server_id  = stackit_server.dsx.server_id
  volume_id  = stackit_volume.config.volume_id
}
resource "stackit_server_volume_attach" "data" {
  project_id = var.project_id
  server_id  = stackit_server.dsx.server_id
  volume_id  = stackit_volume.data.volume_id
}
