# FAQ

## Cloud

### What kinds of cloud can serve models?
Four, from most to least hands-on:
- **Hyperscalers** (AWS, GCP, Azure): GPU VMs, managed Kubernetes, managed ML platforms. Where most customers run, often in their own VPC. New accounts usually start with zero GPU quota, and raising it can take days.
- **GPU clouds** (Lambda, CoreWeave, Nebius, Crusoe): plain VMs or Kubernetes, cheaper than hyperscalers, easier GPU access. Fewer enterprises use them.
- **GPU marketplaces** (RunPod, Vast.ai): cheapest, per-second billing, no quota requests. Good for learning runtimes; rare in customer environments.
- **Serverless inference** (Modal, Baseten, Replicate, HF Inference Endpoints): they hide the infra, so they skip most of the deployment work this lab is for.

### Why RunPod?
Cheap, quick to start, no quota requests. It lets the lab focus on runtimes before fighting hyperscaler setup. Hyperscalers may come later.

### What do RunPod GPUs cost?
List prices per hour from `runpodctl gpu list` on 2026-11-15:

| GPU | Memory | Community | Secure |
|---|---|---|---|
| RTX A4000 | 16 GB | $0.17 | $0.25 |
| RTX 3090 | 24 GB | $0.22 | $0.50 |
| RTX 4090 | 24 GB | $0.34 | $0.89 |
| L4 | 24 GB | – | $0.69 |
| A40 | 48 GB | – | $0.59 |
| A100 80GB | 80 GB | $1.19 | $2.09 |
| H100 SXM | 80 GB | $2.69 | $4.39 |

Community cloud is third-party hardware. Secure cloud is RunPod's own data centers.

### What else costs money besides GPU hours?
Disk, billed per GB per month. A stopped pod keeps charging for its disk, so `tofu destroy` when done instead of stopping.

### Does RunPod's spend limit cap total spending?
No. `spendLimit` (default 80) appears to cap spending per hour (unverified). The prepaid balance is the real limit on total spending, so keep it small.

## RunPod access

### Which permissions does the API key need?
Read and write on all three APIs. Each tool uses a different one:
- REST: the tofu provider (v2 uses only REST).
- GraphQL: `runpodctl`.
- Serverless: calling serverless endpoints.

Give anything that only calls a deployed endpoint its own restricted key.

### Where does the API key live?
In the gitignored `mise.local.toml` as `RUNPOD_API_KEY`. mise loads it per repo, and both tofu and `runpodctl` read it from the environment.

### Should I install RunPod's agent plugin?
Not for now. RunPod's agent setup guide installs a global Claude Code plugin: about 16 skills plus a hosted MCP server whose tools can create and delete pods. That would change infra outside tofu, and it lives in the home directory, not the repo. A docs-only MCP server is the lighter option if it's ever needed.

## Infra as code

### Why IaC instead of the console or CLI?
- Customers manage infra with Terraform, so it's FDE practice.
- `tofu destroy` deletes everything created, which avoids paying for a forgotten GPU pod.
- The same files bring up the same pod again, and git records what changed.

The cost: the RunPod provider is new (v2.0.0, 2026-10-27), iterating is slower than clicking, and a community-cloud host can drop a pod, leaving state stale until the next `plan`.

### What does tofu do, and what does `runpodctl` do?
Tofu creates and destroys resources. `runpodctl` handles one-off tasks: logs, file transfer, SSH, account info (`runpodctl me`).

### Why the full provider source `registry.terraform.io/runpod/runpod`?
The provider isn't on the OpenTofu registry, so a bare `runpod/runpod` doesn't resolve.

### Why must the provider be 2.x?
1.x uses RunPod's REST v1 API, which was switched off on 2026-11-16.

### What from `infra/` goes into git?
The `.tf` files and `.terraform.lock.hcl`, which pins provider versions and checksums. These stay out:
- `*.tfstate`: what tofu last saw of the resources. It can hold secrets in plain text.
- `.terraform/`: provider binaries, which `tofu init` downloads again.

## Serving

### What's a runtime?
A model is a file of numbers, the weights. The runtime, also called the inference server or engine, turns that file into a service:
- loads the weights into GPU memory, possibly quantized
- turns text into tokens and generates the reply one token at a time
- manages the KV cache, the per-request working memory on the GPU, which decides how many requests fit at once
- batches requests, adding new ones as earlier ones finish, which is where most of the throughput comes from
- serves an HTTP API, usually OpenAI-compatible

The weights are the app; the runtime is the app server. The same model can be 2–5× faster on one runtime than another (estimate).

### Which runtimes are there?
- **vLLM**: the production standard, with an OpenAI-compatible API.
- **llama.cpp server**: lighter, runs GGUF quantized models, less common in enterprise.
- **SGLang, TGI**: alternatives to vLLM, worth comparing later.

### What's an instruct model?
A base model trained further to follow instructions and chat:
- **Base**: trained only to predict the next token. Asked a question, it may continue the text instead of answering.
- **Instruct/chat**: the base model further trained on instruction-answer examples and human preferences. It answers, follows the requested format, and stops when done. Names often end in `-Instruct` or `-it`.

Instruct models ship a **chat template**: special tokens marking the system, user and assistant turns. vLLM applies it on `/v1/chat/completions`. A missing or wrong template is a common cause of rambling output. Serve instruct models; use base models as a starting point for fine-tuning.

### Which current models fit one GPU?
Hugging Face, 2026-11-15. All Apache 2.0, ungated, supported by vLLM v0.33.0:

| Model | Params | BF16 weights | Notes |
|---|---|---|---|
| Qwen3.5-4B | 4.7B | ~9.4 GB | text and image; thinking on by default |
| Qwen3.5-9B | 9.7B | ~19.4 GB | needs a 48 GB GPU |
| Gemma 4 E4B-it | 8.0B (~4B effective) | ~16 GB | text, image, audio |
| Granite 4.2 8B | 8.8B | ~17.6 GB | text only, enterprise-focused, little community use |
| Qwen3-8B | 8.2B | ~16.4 GB | older, text only, widely used with vLLM |

BF16 weights take about 2 bytes per parameter. The GPU also needs room for the KV cache and the runtime, so the weights should take well under the GPU's memory.

### Why Qwen3.5-4B first?
Its weights take ~9.4 GB of a 24 GB GPU, leaving plenty for the KV cache, and the family is the most-used of its generation. The Hugging Face download is 9.34 GB: two safetensors files (5.33 + 3.99 GB), including the vision encoder. A fresh host pulls ~19 GB in total, image plus model. Qwen3.5 thinks before answering by default (`<think>...</think>`); turn that off per request for direct answers.

### How big is the vLLM image?
`vllm/vllm-openai:v0.33.0` for amd64 is 9.7 GB compressed, 7.7 GB for the `-x86_64-zstd` tag (Docker Hub). Unpacked it's about 20 GB (estimate). Most of it is CUDA libraries, PyTorch, and kernels for every GPU generation.

It sets the cold start: a host with the image cached started the container in 6 s; a fresh RunPod secure host took ~4 min 50 s to pull it.

### Why vLLM first?
It's the production standard, the one customers most often run. It serves Hugging Face models as they are, through an OpenAI-compatible API, with continuous batching. The cost is a large image and a slow cold start. SGLang makes a good second runtime to compare against it.

## First deploy: Qwen3.5-4B on vLLM

Setup for every number below: Qwen/Qwen3.5-4B, BF16, vLLM v0.33.0, one RTX 4090 (24 GB), RunPod secure cloud (US-NC-1, host CUDA 13.2), `--max-model-len 32768`, 2026-11-15.

### How fast is it?
Measured with `scripts/chat_bench.py` (streamed, one request at a time, ~31-token prompt):

| Run | Completion tokens | TTFT | Decode |
|---|---|---|---|
| thinking off | 390 | 1.34 s | 102.6 tok/s |
| thinking off | 355 | 1.01 s | 102.5 tok/s |
| thinking off | 366 | 1.09 s | 102.6 tok/s |
| thinking on | 1500 (hit limit) | 0.99 s | 101.3 tok/s |

vLLM's own log agreed: 101.2 tok/s in a fully busy 10 s window. TTFT was ~1.0 s from India through RunPod's proxy. A plain `GET /v1/models` round trip took ~0.4 s of that; a 31-token prefill takes milliseconds, so the rest is likely proxy overhead (unverified). With thinking on, all 1500 tokens went to reasoning and no answer came back: thinking needs a much larger `max_tokens`.

### Where does the GPU memory go?
From vLLM's startup log:
- visible: 23.52 GiB; vLLM's target at the default `--gpu-memory-utilization 0.92`: 21.64 GiB
- weights: 8.56 GiB
- CUDA graphs: 0.24 GiB
- KV cache: 10.69 GiB = 314,857 tokens, enough for 9.6 requests at the full 32K context

Qwen3.5 mixes linear attention (Mamba-style state) with regular attention, so its KV cache per token is small.

### How long is a cold start?
About 8 min from `tofu apply` to the first `200`, on a host without the image cached:

| Step | Time |
|---|---|
| pod created | 1 s |
| image pull (9.7 GB) | ~4 min 50 s |
| model download (9.34 GB) and load to GPU | ~1 min (load alone 14.5 s) |
| `torch.compile` | 20.3 s |
| CUDA graph capture, KV cache setup, warmup | ~1.5 min (engine init total 119 s) |

On a host with the image cached, the container started 6 s after apply. The image pull is the part to attack first: a smaller image, a host with it cached, or a network volume holding the weights.

### Is the endpoint public?
Yes. RunPod's HTTP proxy (host `<pod id>-8000.proxy.runpod.net`) is open to the internet. vLLM's `VLLM_API_KEY` env var enforces a bearer key: no key or a wrong key returns 401.

### What did the session cost?
$0.19 in all: ~8 min on a broken community host at $0.34/hr, then ~10 min on a secure 4090 at $0.89/hr. The balance lags: it showed $0.13 spent at teardown and settled a few minutes later.

## Gotchas

### Why did vLLM fail with "CUDA unknown error"?
The host's GPU was broken, not the config. `torch._C._cuda_init()` failed, vLLM's engine never started, and RunPod restarted the container every ~50 s. `tofu apply -replace` landed on the same community host again, likely because few community 4090s had CUDA 13.0 drivers. Secure cloud placed it on a healthy host. Check `runpodctl pod logs <id>` within the first minute, and destroy fast when it loops.

### Why does Python get 403 from RunPod's proxy when curl works?
The proxy rejects urllib's default `User-Agent` (`Python-urllib/...`). Set any other User-Agent.

### Why keep the image's entrypoint?
`vllm/vllm-openai` has entrypoint `vllm serve`. A plain-string `args` on `runpod_pod` becomes the container's cmd and keeps that entrypoint, so `args` starts with the model name. To override the entrypoint too, use the JSON form: `{"entrypoint":[...],"cmd":[...]}`.
