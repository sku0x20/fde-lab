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

### Why vLLM first?
It's the production standard, the one customers most often run. It serves Hugging Face models as they are, through an OpenAI-compatible API, with continuous batching. The cost is a large image and a slow cold start. SGLang makes a good second runtime to compare against it.
