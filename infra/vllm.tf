# Qwen3.5-4B served by vLLM on one RTX 4090 (community cloud)

# the pod's proxy URL is public, so vLLM requires this key on every request.
# kept in state (gitignored); read it with `tofu output -raw vllm_api_key`
resource "random_password" "vllm_api_key" {
  length  = 32
  special = false
}

resource "runpod_pod" "vllm" {
  name  = "vllm-qwen35-4b"
  image = "vllm/vllm-openai:v0.33.0" # entrypoint is `vllm serve`; built on CUDA 13.0

  gpu_type_id      = "NVIDIA GeForce RTX 4090"
  gpu_count        = 1
  cloud            = "COMMUNITY"
  min_cuda_version = "13.0" # hosts with older drivers can't run a CUDA 13.0 image

  # ephemeral, gone on destroy. Holds the Hugging Face download (~9.4 GB); headroom in case
  # the unpacked image (~10 GB compressed) also counts against it
  disk = 60

  # a plain string becomes the container's cmd; the image's entrypoint (`vllm serve`) stays.
  # --host 0.0.0.0: reachable by RunPod's proxy, not just localhost
  # --max-model-len: the 262K default would reserve far more KV cache than 24 GB allows
  # --reasoning-parser: splits Qwen3.5's <think> block into reasoning_content
  args = "Qwen/Qwen3.5-4B --host 0.0.0.0 --port 8000 --max-model-len 32768 --reasoning-parser qwen3"

  env = {
    VLLM_API_KEY = random_password.vllm_api_key.result
  }

  ports = ["8000/http"]
}
