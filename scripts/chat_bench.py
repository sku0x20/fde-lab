"""Stream one chat completion and report TTFT, decode tokens/s and the reply.

usage: VLLM_URL=$(tofu -chdir=infra/vllm output -raw vllm_url) VLLM_KEY=$(tofu -chdir=infra/vllm output -raw vllm_api_key) python3 -I scripts/chat_bench.py [max_tokens] [thinking:0|1]
"""
import json, os, sys, time, urllib.request

url = os.environ["VLLM_URL"] + "/chat/completions"
key = os.environ["VLLM_KEY"]
max_tokens = int(sys.argv[1]) if len(sys.argv) > 1 else 512
thinking = len(sys.argv) > 2 and sys.argv[2] == "1"

body = {
    "model": "Qwen/Qwen3.5-4B",
    "messages": [{"role": "user", "content": "Explain in about 300 words how a KV cache speeds up LLM inference."}],
    "max_tokens": max_tokens,
    "temperature": 0.7,
    "stream": True,
    "stream_options": {"include_usage": True},
    "chat_template_kwargs": {"enable_thinking": thinking},
}
req = urllib.request.Request(url, data=json.dumps(body).encode(), headers={
    "Authorization": f"Bearer {key}", "Content-Type": "application/json",
    # RunPod's proxy answers 403 to urllib's default User-Agent
    "User-Agent": "chat-bench/0.1"})

t0 = time.perf_counter()
first = last = None
content, reasoning, usage = [], [], None
with urllib.request.urlopen(req, timeout=300) as r:
    for raw in r:
        line = raw.decode().strip()
        if not line.startswith("data: ") or line == "data: [DONE]":
            continue
        ev = json.loads(line[6:])
        if ev.get("usage"):
            usage = ev["usage"]
        for ch in ev.get("choices", []):
            d = ch.get("delta", {})
            piece = d.get("content") or d.get("reasoning_content") or d.get("reasoning")
            if piece:
                now = time.perf_counter()
                first = first or now
                last = now
                (content if d.get("content") else reasoning).append(piece)

total = time.perf_counter() - t0
out = usage["completion_tokens"]
print(f"prompt tokens {usage['prompt_tokens']}, completion tokens {out}")
print(f"TTFT {first - t0:.3f} s, total {total:.2f} s")
print(f"decode {(out - 1) / (last - first):.1f} tokens/s (after first token)")
print(f"reasoning chars {len(''.join(reasoning))}")
print("---\n" + "".join(content)[:600])
