# One network volume shared by the vLLM and ComfyUI pods. It outlives them: destroying a pod
# leaves it, so weights download once. It bills monthly whether or not a pod runs; destroy it
# here when done with it for a while.
#
# Layout inside (mounted at /workspace in each pod):
#   huggingface/   vLLM's Hugging Face cache (HF_HOME)
#   runpod-slim/   ComfyUI install, venv and models (the runpod/comfyui image puts it there)

resource "runpod_network_volume" "shared" {
  name = "fde-lab-shared"

  # every pod that mounts it must run here. US-NC-1: had RTX 4090s in secure cloud
  # (first vLLM deploy landed here) and has the S3-compatible API
  data_center = "US-NC-1"

  # GB. Estimate: Z-Image Turbo ~21 + Qwen3.5-4B ~9.4 + ComfyUI venv several, plus headroom.
  # Can grow, never shrink
  size = 50

  # $0.07/GB/month. Immutable; left out, it takes the data center's primary tier, which may
  # be the pricier HIGH_PERFORMANCE
  type = "STANDARD"
}
