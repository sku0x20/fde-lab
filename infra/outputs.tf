output "pod_id" {
  value = runpod_pod.vllm.id
}

# RunPod's HTTP proxy: https://<pod id>-<port>.proxy.runpod.net
output "vllm_url" {
  value = "https://${runpod_pod.vllm.id}-8000.proxy.runpod.net/v1"
}

output "vllm_api_key" {
  value     = random_password.vllm_api_key.result
  sensitive = true
}

output "cost_per_hr" {
  value = runpod_pod.vllm.cost
}
