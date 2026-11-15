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
- **Runtime:** vLLM
- **Infra as code:** OpenTofu (`infra/`, one folder per pod so each comes up and down on its own), with `runpodctl` for one-off tasks (logs, SSH, file transfer)
- **Tool versions:** pinned in `mise.toml`

## Layout

| Path | What |
|---|---|
| `infra/vllm/` | OpenTofu config: a RunPod pod serving a model with vLLM, its API key and outputs |
| `webui/compose.yaml` | Open WebUI on the laptop, pointed at the vLLM pod |
| `scripts/chat_bench.py` | Streams one chat completion and reports TTFT and decode tokens/s |
| `FAQ.md` | Notes: concepts, decisions and their why, gotchas, measured numbers |

## Run it

These steps rent a GPU, so they cost money. A pod bills until you destroy it.

```sh
mise install
# create mise.local.toml (gitignored) holding RUNPOD_API_KEY
cat > mise.local.toml <<'EOF'
[env]
RUNPOD_API_KEY = "..."
EOF

tofu -chdir=infra/vllm init
tofu -chdir=infra/vllm apply      # cold start takes ~8 min, mostly the image pull

VLLM_URL=$(tofu -chdir=infra/vllm output -raw vllm_url) \
VLLM_KEY=$(tofu -chdir=infra/vllm output -raw vllm_api_key) \
python3 -I scripts/chat_bench.py

tofu -chdir=infra/vllm destroy    # destroy, don't stop: a stopped pod still bills for disk
```

## Results so far

Qwen3.5-4B (BF16) on vLLM v0.33.0, one RTX 4090, RunPod secure cloud:

- decode: ~102 tok/s for a single request
- TTFT: ~1.0 s, measured from India through RunPod's proxy
- cold start: ~8 min
- cost: $0.89/hr

`FAQ.md` has the full numbers and how they were measured.
