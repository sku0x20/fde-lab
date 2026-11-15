"""Times Z-Image Turbo text-to-image runs on ComfyUI through the SSH tunnel.

usage: python3 -I scripts/comfyui_bench.py [runs] [size]
  needs: ssh -F .ssh/config -N -L 8188:localhost:8188 comfyui
  runs: default 3 (the first also loads the models), size: default 1024 (square)

Graph and settings are ComfyUI's bundled image_z_image_turbo template: 8 steps, cfg 1,
res_multistep/simple, AuraFlow shift 3. Images land in ComfyUI's output/ on the pod.
"""

import json
import sys
import time
import urllib.request
import uuid

URL = "http://localhost:8188"
PROMPT = "a red fox in fresh snow at dawn, soft golden light, shallow depth of field, photo"


def graph(seed: int, size: int) -> dict:
    return {
        "unet": {"class_type": "UNETLoader", "inputs": {"unet_name": "z_image_turbo_bf16.safetensors", "weight_dtype": "default"}},
        "clip": {"class_type": "CLIPLoader", "inputs": {"clip_name": "qwen_3_4b.safetensors", "type": "lumina2", "device": "default"}},
        "vae": {"class_type": "VAELoader", "inputs": {"vae_name": "ae.safetensors"}},
        "shift": {"class_type": "ModelSamplingAuraFlow", "inputs": {"model": ["unet", 0], "shift": 3}},
        "pos": {"class_type": "CLIPTextEncode", "inputs": {"clip": ["clip", 0], "text": PROMPT}},
        "neg": {"class_type": "ConditioningZeroOut", "inputs": {"conditioning": ["pos", 0]}},
        "latent": {"class_type": "EmptySD3LatentImage", "inputs": {"width": size, "height": size, "batch_size": 1}},
        "sample": {
            "class_type": "KSampler",
            "inputs": {
                "model": ["shift", 0], "positive": ["pos", 0], "negative": ["neg", 0], "latent_image": ["latent", 0],
                "seed": seed, "steps": 8, "cfg": 1, "sampler_name": "res_multistep", "scheduler": "simple", "denoise": 1,
            },
        },
        "decode": {"class_type": "VAEDecode", "inputs": {"samples": ["sample", 0], "vae": ["vae", 0]}},
        "save": {"class_type": "SaveImage", "inputs": {"images": ["decode", 0], "filename_prefix": "bench"}},
    }


def call(path: str, body: dict | None = None) -> dict:
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(URL + path, data=data, headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.load(r)


def run(seed: int, size: int) -> float:
    start = time.monotonic()
    pid = call("/prompt", {"prompt": graph(seed, size), "client_id": str(uuid.uuid4())})["prompt_id"]
    while True:
        h = call(f"/history/{pid}").get(pid)
        if h and h.get("status", {}).get("completed"):
            return time.monotonic() - start
        if h and h.get("status", {}).get("status_str") == "error":
            sys.exit(f"run failed: {json.dumps(h['status'])[:800]}")
        time.sleep(0.2)


def main() -> None:
    runs = int(sys.argv[1]) if len(sys.argv) > 1 else 3
    size = int(sys.argv[2]) if len(sys.argv) > 2 else 1024
    for i in range(runs):
        # new seed each run, or ComfyUI returns the cached result
        secs = run(seed=int(time.time() * 1000) % 2**32, size=size)
        print(f"run {i + 1}: {secs:.2f} s ({size}x{size}, 8 steps){'  <- includes model load' if i == 0 else ''}")


if __name__ == "__main__":
    main()
