# fde-lab

A personal lab for forward deployed engineer (FDE) skills: taking models and AI systems into a customer's environment and making them work there.

It starts with deployment: serving open models on rented cloud GPUs. Nothing runs locally.

## Roadmap

Models always run on RunPod. Only clients run on the laptop.

- [ ] **1. Browser chat app**: Open WebUI, a Docker image.
  - [x] 1.1 Run the container on the laptop, pointed at the pod.
  - [ ] 1.2 Deploy it to a RunPod CPU pod with OpenTofu, next to the vLLM pod. Then it works from a phone browser too, and installs to the home screen as a web app.
- [ ] **2. Agent harness**: OpenCode driving the vLLM pod. Needs vLLM's tool-call flags; tests context size and how a small model handles tools.
- [ ] **3. Image and video generation**: ComfyUI on a GPU pod. Images first.
  - [ ] 3.1 Use it from the laptop: ComfyUI's browser UI or a local client.
  - [ ] 3.2 A server-side frontend, possibly on RunPod serverless.

Later, maybe: native chat apps for phone or desktop. Skipped for now in favour of the browser.

## Stack

- **Cloud:** RunPod
- **Runtimes:** vLLM (LLMs), ComfyUI (images)
- **Infra as code:** OpenTofu (`infra/`, one folder per pod plus one for the shared volume, each with its own state, so each comes up and down on its own), with `runpodctl` for one-off tasks (logs, SSH, file transfer)
- **Tool versions:** pinned in `mise.toml`

## Layout

| Path | What |
|---|---|
| `infra/persistence/` | OpenTofu config: the network volume both pods mount at `/workspace`, so weights download once. Outlives the pods |
| `infra/vllm/` | OpenTofu config: a RunPod pod serving a model with vLLM, its API key and outputs |
| `infra/comfyui/` | OpenTofu config: a RunPod pod running ComfyUI, reached over an SSH tunnel |
| `webui/compose.yaml` | Open WebUI on the laptop, pointed at the vLLM pod |
| `scripts/ssh_config.sh` | Writes `.ssh/config` for a pod, so SSH uses the repo's key and known_hosts |
| `scripts/comfyui_models.sh` | Downloads Z-Image Turbo onto the volume; run on the ComfyUI pod over SSH |
| `scripts/comfyui_bench.py` | Times Z-Image Turbo text-to-image runs on ComfyUI through the tunnel |
| `scripts/chat_bench.py` | Streams one chat completion and reports TTFT and decode tokens/s |
| `FAQ.md` | Notes: concepts, decisions and their why, gotchas, measured numbers |

## Run it

These steps rent a GPU, so they cost money. A pod bills by the hour until you destroy it; the volume bills by the month until you destroy it.

```sh
mise install
# create mise.local.toml (gitignored) holding RUNPOD_API_KEY
cat > mise.local.toml <<'EOF'
[env]
RUNPOD_API_KEY = "..."
EOF

for d in persistence vllm comfyui; do tofu -chdir=infra/$d init; done
```

### The volume (first up, last down)

```sh
tofu -chdir=infra/persistence apply      # 50 GB in EU-RO-1, ~$3.50/month
tofu -chdir=infra/persistence destroy    # deletes the weights; destroy the pods first
```

### vLLM

```sh
tofu -chdir=infra/vllm apply      # cold start takes ~8 min, mostly the image pull

VLLM_URL=$(tofu -chdir=infra/vllm output -raw vllm_url) \
VLLM_KEY=$(tofu -chdir=infra/vllm output -raw vllm_api_key) \
python3 -I scripts/chat_bench.py

tofu -chdir=infra/vllm destroy    # destroy, don't stop: a stopped pod still bills for disk
```

### ComfyUI

SSH uses the repo's gitignored `.ssh/` (key, config, known_hosts), never `~/.ssh`.

```sh
mkdir -m 700 .ssh && ssh-keygen -t ed25519 -f .ssh/runpod_ed25519    # once
tofu -chdir=infra/comfyui apply

# writes .ssh/config with the pod's direct SSH host and port; rerun per pod
scripts/ssh_config.sh comfyui $(tofu -chdir=infra/comfyui output -raw pod_id)

# once per volume: download Z-Image Turbo (~21 GB)
ssh -F .ssh/config comfyui 'bash -s' < scripts/comfyui_models.sh

# tunnel, then open http://localhost:8188
ssh -F .ssh/config -N -L 8188:localhost:8188 comfyui
python3 -I scripts/comfyui_bench.py    # in another terminal, with the tunnel up

tofu -chdir=infra/comfyui destroy
```

## Results so far

Qwen3.5-4B (BF16) on vLLM v0.33.0, one RTX 4090, RunPod secure cloud:

- decode: ~102 tok/s for a single request
- TTFT: ~1.0 s, measured from India through RunPod's proxy
- cold start: ~8 min
- cost: $0.89/hr

Z-Image Turbo (bf16) on ComfyUI v0.44.0, one RTX 4090, RunPod secure cloud:

- ~5.0 s per 1024x1024 image (8 steps)
- first image after boot: ~75 s, loading the weights from the network volume
- cold start: ~6 min to serving; first boot on a new volume adds ~5 min of model download
- cost: $0.89/hr for the pod, plus ~$3.50/month for the 50 GB volume

`FAQ.md` has the full numbers and how they were measured.
