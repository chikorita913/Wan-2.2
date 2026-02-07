import json
import time
import uuid
import os
import requests
import websocket
import subprocess

COMFY_HOST = "127.0.0.1:8188"


def wait_for_comfy(timeout_s=60):
    start = time.time()
    while time.time() - start < timeout_s:
        try:
            r = requests.get(f"http://{COMFY_HOST}/", timeout=2)
            if r.status_code == 200:
                return
        except Exception:
            pass
        time.sleep(0.5)
    raise RuntimeError("ComfyUI did not become available")


def queue_workflow(workflow):
    client_id = str(uuid.uuid4())
    payload = {
        "prompt": workflow,
        "client_id": client_id,
    }

    r = requests.post(
        f"http://{COMFY_HOST}/prompt",
        json=payload,
        timeout=30,
    )
    r.raise_for_status()
    prompt_id = r.json().get("prompt_id")
    if not prompt_id:
        raise RuntimeError("Missing prompt_id from ComfyUI")

    return client_id, prompt_id


def wait_for_completion(client_id, prompt_id, timeout_s=600):
    ws = websocket.WebSocket()
    ws.connect(f"ws://{COMFY_HOST}/ws?clientId={client_id}", timeout=10)

    start = time.time()
    try:
        while time.time() - start < timeout_s:
            msg = json.loads(ws.recv())
            if msg.get("type") == "execution_error":
                raise RuntimeError(f"Execution error: {msg}")
            if msg.get("type") == "executing":
                data = msg.get("data", {})
                if data.get("node") is None and data.get("prompt_id") == prompt_id:
                    return
    finally:
        ws.close()

    raise RuntimeError("Execution timed out")


def get_history(prompt_id):
    r = requests.get(f"http://{COMFY_HOST}/history/{prompt_id}", timeout=30)
    r.raise_for_status()
    history = r.json()
    if prompt_id not in history:
        raise RuntimeError("Prompt not found in history")
    return history[prompt_id]


def extract_video_artifacts(history_entry):
    videos = []
    outputs = history_entry.get("outputs", {})
    for node_output in outputs.values():
        if "videos" in node_output:
            videos.extend(node_output["videos"])
    return videos


def resolve_video_path(video):
    filename = video["filename"]
    subfolder = video.get("subfolder", "")
    return os.path.join("/comfyui/output", subfolder, filename)


def validate_mp4(path):
    if not os.path.exists(path):
        raise RuntimeError(f"Video file missing: {path}")
    if os.path.getsize(path) < 10_000:
        raise RuntimeError(f"Video file too small: {path}")

    result = subprocess.run(
        ["ffprobe", "-v", "error", path],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    if result.returncode != 0:
        raise RuntimeError(f"ffprobe failed on {path}")


