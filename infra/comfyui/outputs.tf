output "pod_id" {
  value = runpod_pod.comfyui.id
}

output "cost_per_hr" {
  value = runpod_pod.comfyui.cost
}

# the direct SSH host and port exist only once the pod runs: `runpodctl ssh info <pod_id>`
