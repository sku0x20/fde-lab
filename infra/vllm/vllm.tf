# Qwen3.5-4B served by vLLM on one RTX 4090 (secure cloud), weights on the shared network volume

# the pod's proxy URL is public, so vLLM requires this key on every request.
# kept in state (gitignored); read it with `tofu output -raw vllm_api_key`
resource "random_password" "vllm_api_key" {
  length  = 32
  special = false
}

resource "runpod_pod" "vllm" {
  name  = "vllm-qwen35-4b"
  image = "vllm/vllm-openai:v0.33.0" # entrypoint is `vllm serve`; built on CUDA 13.0

  gpu_type_id = "NVIDIA GeForce RTX 4090"
  gpu_count   = 1
  # community kept landing on one host whose GPU failed CUDA init, likely because few
  # community 4090s have CUDA 13.0 drivers
  cloud            = "SECURE"
  min_cuda_version = "13.0" # hosts with older drivers can't run a CUDA 13.0 image

  # the volume pins the pod to its data center
  data_center_ids = [data.terraform_remote_state.persistence.outputs.data_center]
  network_volumes = [{
    volume_id = data.terraform_remote_state.persistence.outputs.volume_id
    path      = "/workspace"
  }]

  # ephemeral, gone on destroy. The weights now go to the volume (HF_HOME); this holds the
  # unpacked image (~10 GB compressed) with headroom
  disk = 60

  # a plain string becomes the container's cmd; the image's entrypoint (`vllm serve`) stays.
  # --host 0.0.0.0: reachable by RunPod's proxy, not just localhost
  # --max-model-len: the 262K default would reserve far more KV cache than 24 GB allows
  # --reasoning-parser: splits Qwen3.5's <think> block into reasoning_content
  # --enable-auto-tool-choice, --tool-call-parser: accept `tools` and turn the model's tool-call
  #   output into tool_calls. Open WebUI sends tools on every chat. Parser from the model card
  args = "Qwen/Qwen3.5-4B --host 0.0.0.0 --port 8000 --max-model-len 32768 --reasoning-parser qwen3 --enable-auto-tool-choice --tool-call-parser qwen3_coder"

  env = {
    VLLM_API_KEY = random_password.vllm_api_key.result
    # Hugging Face cache on the volume, so the ~9.4 GB download happens once per volume
    HF_HOME = "/workspace/huggingface"
  }

  ports = ["8000/http"]
}
