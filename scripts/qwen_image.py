"""Generate or edit images with Qwen-Image 2.1 Turbo on ComfyUI, through the SSH tunnel.

usage:
  python3 -I scripts/qwen_image.py gen  "<prompt>"               [-n N] [--enhance] [--aspect A]
  python3 -I scripts/qwen_image.py edit <image> "<instruction>"  [-n N] [--enhance]
  needs: ssh -F .ssh/config -N -L 8188:localhost:8188 comfyui

--enhance turns on the workflow's prompt rewriter (a Qwen3.5-9B that expands a rough prompt
into a detailed one); the rewritten prompt is printed. Images are saved to tmp/out/.

The graphs are ComfyUI's image_qwen_image_2_1_turbo_t2i / _image_edit templates, exported in
API format to workflows/. Node IDs below point into those files.
"""

import argparse
import copy
import json
import mimetypes
import pathlib
import sys
import time
import urllib.parse
import urllib.request
import uuid

URL = "http://localhost:8188"
ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "tmp" / "out"

# node ids in the exported graphs
T2I = {
    "file": "qwen_image_2.1_turbo_t2i.api.json",
    "prompt": [("459:471", "prompt"), ("459:474", "on_false")],  # rewriter input, rewriter-off path
    "switch": ("459:474", "switch"),
    "seed": [("459:488", "noise_seed"), ("459:471", "sampling_mode.seed")],
    "aspect": ("13", "aspect_ratio"),
    "preview": "459:472",
    "save": "461",
}
EDIT = {
    "file": "qwen_image_2.1_turbo_edit.api.json",
    "prompt": [("459:500", "prompt"), ("459:484", "on_false")],
    "switch": ("459:484", "switch"),
    "seed": [("459:504", "noise_seed"), ("459:500", "sampling_mode.seed")],
    "image": ("470", "image"),
    "preview": "459:480",
    "save": "461",
}


def call(path: str, body: bytes | None = None, ctype: str = "application/json") -> dict:
    req = urllib.request.Request(URL + path, data=body, headers={"Content-Type": ctype})
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.load(r)


def upload(image: pathlib.Path) -> str:
    """Uploads a local image to ComfyUI's input/ folder; returns the name it got there."""
    boundary = uuid.uuid4().hex
    ctype = mimetypes.guess_type(image.name)[0] or "application/octet-stream"
    body = (
        f'--{boundary}\r\nContent-Disposition: form-data; name="image"; filename="{image.name}"\r\n'
        f"Content-Type: {ctype}\r\n\r\n"
    ).encode() + image.read_bytes() + (
        f'\r\n--{boundary}\r\nContent-Disposition: form-data; name="overwrite"\r\n\r\ntrue\r\n--{boundary}--\r\n'
    ).encode()
    r = call("/upload/image", body, f"multipart/form-data; boundary={boundary}")
    return f"{r['subfolder']}/{r['name']}" if r.get("subfolder") else r["name"]


def run(graph: dict, ids: dict) -> tuple[float, list[pathlib.Path], str]:
    start = time.monotonic()
    body = json.dumps({"prompt": graph, "client_id": str(uuid.uuid4())}).encode()
    pid = call("/prompt", body)["prompt_id"]
    while True:
        h = call(f"/history/{pid}").get(pid)
        status = (h or {}).get("status", {})
        if status.get("completed"):
            break
        if status.get("status_str") == "error":
            sys.exit(f"run failed: {json.dumps(status)[:1500]}")
        time.sleep(0.3)
    secs = time.monotonic() - start

    OUT.mkdir(parents=True, exist_ok=True)
    paths = []
    for img in h["outputs"][ids["save"]]["images"]:
        q = urllib.parse.urlencode({"filename": img["filename"], "subfolder": img["subfolder"], "type": img["type"]})
        dest = OUT / img["filename"]
        with urllib.request.urlopen(f"{URL}/view?{q}", timeout=60) as r:
            dest.write_bytes(r.read())
        paths.append(dest)
    text = h["outputs"].get(ids["preview"], {}).get("text", [""])
    return secs, paths, text[0] if isinstance(text, list) and text else str(text)


def main() -> None:
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    g = sub.add_parser("gen")
    g.add_argument("prompt")
    g.add_argument("--aspect", help='e.g. "16:9 (Widescreen)"; default the template\'s 1:1')
    e = sub.add_parser("edit")
    e.add_argument("image", type=pathlib.Path)
    e.add_argument("prompt")
    for p in (g, e):
        p.add_argument("-n", type=int, default=1, help="images to make, one seed each")
        p.add_argument("--enhance", action="store_true", help="rewrite the prompt with the workflow's LLM first")
    a = ap.parse_args()

    ids = T2I if a.cmd == "gen" else EDIT
    base = json.loads((ROOT / "workflows" / ids["file"]).read_text())
    for node, key in ids["prompt"]:
        base[node]["inputs"][key] = a.prompt
    node, key = ids["switch"]
    base[node]["inputs"][key] = a.enhance
    if a.cmd == "gen" and a.aspect:
        node, key = ids["aspect"]
        base[node]["inputs"][key] = a.aspect
    if a.cmd == "edit":
        node, key = ids["image"]
        base[node]["inputs"][key] = upload(a.image)

    for i in range(a.n):
        graph = copy.deepcopy(base)
        seed = int(time.time() * 1000) % 2**48  # a new seed each run, or ComfyUI returns the cached result
        for node, key in ids["seed"]:
            graph[node]["inputs"][key] = seed
        secs, paths, text = run(graph, ids)
        print(f"run {i + 1}: {secs:.2f} s -> {', '.join(str(p.relative_to(ROOT)) for p in paths)}")
        if a.enhance and text:
            print(f"  rewritten prompt: {text}")


if __name__ == "__main__":
    main()
