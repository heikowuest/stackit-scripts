moved {
  from = stackit_image.config
  to   = stackit_image.config[0]
}

moved {
  from = stackit_volume.config
  to   = stackit_volume.config[0]
}

moved {
  from = stackit_volume.data
  to   = stackit_volume.data[0]
}

moved {
  from = stackit_server_volume_attach.config
  to   = stackit_server_volume_attach.config[0]
}

moved {
  from = stackit_server_volume_attach.data
  to   = stackit_server_volume_attach.data[0]
}
