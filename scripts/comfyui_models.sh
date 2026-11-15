#!/usr/bin/env bash
# Downloads Qwen-Image 2.1 Turbo (~36 GB, 8-bit) into ComfyUI's models folder on the shared
# network volume: the files ComfyUI's image_qwen_image_2_1_turbo_t2i and
# image_qwen_image_2_1_turbo_image_edit templates load. Runs on the ComfyUI pod, once per
# volume; files already there are skipped.
#
# usage, from the laptop (after start.sh has copied ComfyUI to /workspace/runpod-slim):
#   ssh -F .ssh/config comfyui 'bash -s' < scripts/comfyui_models.sh
set -euo pipefail

models=/workspace/runpod-slim/ComfyUI/models
repo=https://huggingface.co/Comfy-Org/Qwen-Image-2.1/resolve/main

# <subfolder>/<file>, the same path in the repo and under models/
files=(
  diffusion_models/qwen_image_2.1_turbo_int8_convrot.safetensors           # 7.26 GB, the image model
  text_encoders/qwen3vl_8b_int8_convrot.safetensors                        # 9.35 GB, reads prompt (and image, for edits)
  text_encoders/qwen3.5_9b_qwen_image_2.1_pe_t2i.int8_convrot.safetensors # 9.47 GB, prompt rewriter, text-to-image
  text_encoders/qwen3.5_9b_qwen_image_2.1_pe_i2i.int8_convrot.safetensors # 9.47 GB, prompt rewriter, edits
  vae/qwen_image_2.1_vae_bf16.safetensors                                  # 0.68 GB
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
  curl -fsSL --retry 3 -C - -o "$dest.part" "$repo/$f"
  mv "$dest.part" "$dest"
done

du -sh "$models"/{diffusion_models,text_encoders,vae}
