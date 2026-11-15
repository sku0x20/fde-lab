# ComfyUI on one RTX 4090 (secure cloud), image models on the shared network volume.
# Reached only over an SSH tunnel: ComfyUI has no auth, so its port stays off the public proxy.

variable "ssh_public_key_path" {
  description = "Public key allowed to SSH in as root"
  type        = string
  default     = "~/.ssh/runpod_ed25519.pub"
}

resource "runpod_pod" "comfyui" {
  name = "comfyui"
  # RunPod's official ComfyUI image: ComfyUI v0.44.0 + ComfyUI-Manager, CUDA 12.8, no models.
  # Its start.sh copies ComfyUI to /workspace/runpod-slim on first boot, then runs it on 8188
  image = "runpod/comfyui:2.2.0-comfyuiv0.44.0-cuda12.8"

  gpu_type_id      = "NVIDIA GeForce RTX 4090"
  gpu_count        = 1
  cloud            = "SECURE" # network volumes are secure cloud only
  min_cuda_version = "12.8"   # hosts with older drivers can't run a CUDA 12.8 image

  # the volume pins the pod to its data center
  data_center_ids = [data.terraform_remote_state.persistence.outputs.data_center]
  network_volumes = [{
    volume_id = data.terraform_remote_state.persistence.outputs.volume_id
    path      = "/workspace" # the image keeps ComfyUI, its venv and models under /workspace
  }]

  # ephemeral, gone on destroy: only the unpacked image (~5.4 GB compressed) lives here
  disk = 30

  # no args or entrypoint: the image's start.sh must run
  env = {
    # start.sh adds it to root's authorized_keys. Without it, start.sh sets a random root
    # password (printed in the logs) and sshd accepts passwords
    PUBLIC_KEY = trimspace(file(pathexpand(var.ssh_public_key_path)))
  }

  # SSH only. 8188 (ComfyUI, no auth), 8888 (Jupyter, empty token) and 8080 (FileBrowser,
  # default password) stay unexposed; reach them through the tunnel
  ports = ["22/tcp"]
}
