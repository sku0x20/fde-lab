output "volume_id" {
  value = runpod_network_volume.shared.id
}

output "data_center" {
  value = runpod_network_volume.shared.data_center
}
