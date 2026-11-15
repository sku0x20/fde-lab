# fde-lab

A personal lab for forward deployed engineer (FDE) skills: taking models and AI systems into a customer's environment and making them work there.

It starts with deployment: serving open models on rented cloud GPUs. Nothing runs locally.

## Stack

- **Cloud:** RunPod
- **Runtime:** vLLM
- **Infra as code:** OpenTofu (`infra/`), with `runpodctl` for one-off tasks (logs, SSH, file transfer)
- **Tool versions:** pinned in `mise.toml`

## Layout

| Path | What |
|---|---|
| `infra/` | OpenTofu config: a RunPod pod serving a model with vLLM, its API key and outputs |
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

tofu -chdir=infra init
tofu -chdir=infra apply      # cold start takes ~8 min, mostly the image pull

VLLM_URL=$(tofu -chdir=infra output -raw vllm_url) \
VLLM_KEY=$(tofu -chdir=infra output -raw vllm_api_key) \
python3 -I scripts/chat_bench.py

tofu -chdir=infra destroy    # destroy, don't stop: a stopped pod still bills for disk
```

## Results so far

Qwen3.5-4B (BF16) on vLLM v0.33.0, one RTX 4090, RunPod secure cloud:

- decode: ~102 tok/s for a single request
- TTFT: ~1.0 s, measured from India through RunPod's proxy
- cold start: ~8 min
- cost: $0.89/hr

`FAQ.md` has the full numbers and how they were measured.
