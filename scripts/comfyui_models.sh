#!/usr/bin/env bash
# Downloads Z-Image Turbo (~20.7 GB) into ComfyUI's models folder on the shared network volume.
# Runs on the ComfyUI pod, once per volume; files already there are skipped.
#
# usage, from the laptop (after start.sh has copied ComfyUI to /workspace/runpod-slim):
#   ssh -F .ssh/config comfyui 'bash -s' < scripts/comfyui_models.sh
set -euo pipefail

models=/workspace/runpod-slim/ComfyUI/models
repo=https://huggingface.co/Comfy-Org/Z-Image-Turbo/resolve/main/split_files

# <subfolder>/<file>: bf16 weights (nvfp4 needs a Blackwell GPU), full text encoder, VAE
files=(
  diffusion_models/z_image_turbo_bf16.safetensors # 12.31 GB
  text_encoders/qwen_3_4b.safetensors             # 8.04 GB
  vae/ae.safetensors                              # 0.34 GB
)

for f in "${files[@]}"; do
  dest="$models/$f"
  if [[ -f $dest ]]; then
    echo "have $f"
    continue
  fi
  mkdir -p "$(dirname "$dest")"
  echo "get  $f"
  # .part until complete, so an interrupted run resumes (-C -) instead of leaving a bad file
  curl -fL --retry 3 -C - -o "$dest.part" "$repo/$f"
  mv "$dest.part" "$dest"
done

du -sh "$models"/{diffusion_models,text_encoders,vae}
