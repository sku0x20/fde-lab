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

## Frontend

### Which chat frontends work with a vLLM endpoint?
Any that speak the OpenAI API: point it at the `/v1` base URL with the vLLM key.
- **Open WebUI**: the usual pick for self-hosted models. ChatGPT-like, multi-user, chat history, RAG. One container, server-side.
- **LibreChat**: also full-featured, built for many providers at once. Needs MongoDB and more, so heavier to run.
- **LobeChat, NextChat**: lighter and polished, but can run client-side, which puts the API key in the browser.
- **Your own (Gradio, Streamlit, a small web app)**: a few dozen lines on the OpenAI SDK. It's what a customer's product usually ends up being.
- **Desktop chat apps (Jan, Msty, Chatbox, Cherry Studio)**: no hosting, but they run on the laptop. LM Studio and Ollama are local runtimes, not clients for a remote endpoint.

vLLM ships no chat UI of its own.

### What's a harness?
The program around a model that turns it into an agent. The model only maps text to text; the harness supplies:
- the system prompt and tool definitions (read, edit, run shell, search)
- the loop: call the model, run the tool it asks for, send the result back, repeat until done
- context management: what goes in the window, compaction when it fills
- permissions: which actions need a human's OK

Claude Code is a harness. So are OpenCode, Aider, Goose and Codex CLI in the terminal, and Cline, Roo Code and Continue in the IDE. A chat app is not: it sends messages but runs no tools.

### Why use another harness if Claude Code works?
For daily coding, no reason. Claude Code is tuned for Claude models. The others are model-agnostic: they can drive any OpenAI-compatible endpoint, including a self-hosted vLLM model. That's the FDE use: customers who can't send code to a hosted API want a coding agent on their own model. It tests the deployment, not the harness:
- vLLM must parse tool calls (`--enable-auto-tool-choice` plus a `--tool-call-parser` for the model), or the agent can't use tools.
- Agent system prompts and tool definitions are large, so `--max-model-len` and the KV cache matter more than in chat.
- Small models (4B) are weak at multi-step tool use; expect a chat app to work well before an agent does.

### Where does the frontend run?
A RunPod pod runs one container, so the frontend can't share the vLLM pod without a custom image. The options are a separate CPU pod (fits the IaC, costs a little per hour), the laptop, or a free host for a small custom app. A server-side frontend keeps the vLLM key off the browser.

## Image and video generation

### Can the current setup generate images?
No. Qwen3.5-4B takes images as input (understanding) but outputs only text. Generating images or video takes a different kind of model, diffusion, and usually a different runtime, API and frontend.

### What changes compared to serving an LLM?
| | LLM (now) | Image / video diffusion |
|---|---|---|
| How it generates | one token at a time, streamed | refines the whole image (or clip) from noise over 20–50 steps |
| Bottleneck | memory bandwidth (decode) | compute |
| GPU memory | weights + KV cache | weights + text encoder + VAE; no KV cache. Video is the tightest fit |
| Batching | continuous, big throughput win | helps less |
| Metrics | TTFT, tokens/s | seconds per image, minutes per video clip |
| API shape | request/response, streamed | long-running jobs: submit, poll, fetch a file. Outputs need storage |
| Runtime | vLLM | ComfyUI (de facto standard, node graphs, has its own UI and API) or diffusers (a Python library; write your own server) |
| Frontend | chat app or harness | ComfyUI's UI, or Open WebUI with ComfyUI as its image backend |
| Licenses | mostly Apache 2.0 | mixed; some popular weights are non-commercial, which matters for customers |

### Where do harnesses fit?
An agent doesn't generate images itself. It calls an image model as a tool, for example through an MCP server in front of ComfyUI. The LLM plans and writes the prompt; the diffusion model draws.

### What fits RunPod for this?
Pods work the same way. Long jobs with idle time between them fit RunPod serverless better (submit a job, pay per second of run). ComfyUI setups depend on custom nodes and model files in exact folders, so reproducing one is harder than `vllm serve <model>`; a network volume or a custom image holds them.

## Tokens

### What's a token?
A chunk of text from the model's fixed vocabulary (Qwen3.5: 248,320 tokens). A common word is one token, a rare word several; in English a token is about ¾ of a word (estimate). The model reads and writes token IDs, so limits, speed and billing are all counted in tokens.
- **prompt tokens**: the input, including the chat template's markers
- **completion tokens**: what the model generates

### How does generation work?
Two phases:
1. **Prefill**: all prompt tokens are processed at once, in parallel. Fast.
2. **Decode**: output comes one token at a time, each depending on all the tokens before it. Can't be parallelized within one request.

### Why ~100 tokens/s for one request on a 4090?
Each decode step reads all the weights from GPU memory. An RTX 4090 moves ~1,000 GB/s and the weights are 9.2 GB (8.56 GiB), so one request tops out at ~110 tok/s (estimate). Measured: 102. Single-stream decode is limited by memory bandwidth, not compute. Batching reuses each read of the weights across many requests, which is where serving throughput comes from.

### How does batching work?
Many requests share each GPU step. The step is dominated by reading the weights (9.2 GB), so one read can produce the next token for 32 requests nearly as fast as for 1. Total throughput rises many times over; each stream slows only a little.

- **Static batching**: run N requests together and wait for all of them to finish. Short answers idle while long ones finish, and new requests wait for the whole batch.
- **Continuous batching** (vLLM): the batch is rebuilt at every token step. A finished request leaves straight away and a waiting one takes its slot, so the GPU stays full.
- **Chunked prefill**: a long new prompt is split into chunks mixed into decode steps, so it doesn't stall everyone else's streaming.

Limits:
- KV cache memory: every request in flight holds its own cache. When it fills, vLLM queues or pauses requests.
- compute: at large batches the GPU becomes compute-bound, so total throughput levels off and each stream slows down.
- `--max-num-seqs`: a cap on requests running at once.
- latency: bigger batches give more total tok/s but slower per-user streaming and higher TTFT. Tuning that balance against a latency target is core deployment work.

### What's TTFT?
Time to first token: network + queueing + prefill. How long until the reply starts. Decode tok/s is how fast it then streams.

### What's the KV cache?
Attention makes each new token look back at all earlier ones. To avoid recomputing them, the model stores a key and a value vector per token per attention layer. That's the KV cache. It grows with context length, so it caps how much text and how many requests fit on the GPU. Qwen3.5-4B: ~36 KiB per token, small because only 8 of its 32 layers use full attention; the other 24 use linear attention with a fixed-size state.

### What's the difference between `--max-model-len` and `max_tokens`?
- `--max-model-len` (server): the most context one request can use, prompt plus output. vLLM checks at startup that one full-length request fits in the KV cache.
- `max_tokens` (request): the most output tokens to generate. The model usually stops sooner, at its end-of-answer token.

Prompt + `max_tokens` must fit within `--max-model-len`.

### What does "maximum concurrency 9.61x for 32,768 tokens" mean?
KV cache tokens ÷ `--max-model-len`: 314,857 ÷ 32,768 = 9.6. If every request used the full 32K context, 9 could run at once. Real requests are shorter: at ~420 tokens each, ~750 would fit. vLLM hands out the cache in small pages as requests grow (PagedAttention), not 32K upfront. `--max-num-seqs` also caps how many run at once.

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

### How does `scripts/chat_bench.py` measure?
It sends one streamed request (`stream: true`), so tokens arrive as server-sent events, and timestamps them:
- TTFT = first text chunk − request sent
- decode tok/s = (completion tokens − 1) ÷ (last chunk − first chunk), which leaves out network and prefill

`stream_options.include_usage` gives exact token counts. `chat_template_kwargs.enable_thinking` turns Qwen's thinking on or off. RunPod's proxy rejects urllib's default User-Agent, so the script sets its own.

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
