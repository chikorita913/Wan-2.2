import json
import sys

from comfy_client import (
    wait_for_comfy,
    queue_workflow,
    wait_for_completion,
    get_history,
    extract_video_artifacts,
    resolve_video_path,
    validate_mp4,
)

WARMUP_WORKFLOW_PATH = "/warmup_workflow.json"


def main():
    print("[warmup] waiting for ComfyUI...")
    wait_for_comfy()

    print("[warmup] loading workflow...")
    with open(WARMUP_WORKFLOW_PATH, "r") as f:
        workflow = json.load(f)

    print("[warmup] queueing workflow...")
    client_id, prompt_id = queue_workflow(workflow)

    print("[warmup] waiting for execution...")
    wait_for_completion(client_id, prompt_id)

    print("[warmup] fetching history...")
    history = get_history(prompt_id)

    videos = extract_video_artifacts(history)
    if not videos:
        raise RuntimeError("No video artifacts produced during warmup")

    print(f"[warmup] validating {len(videos)} video(s)...")
    for video in videos:
        path = resolve_video_path(video)
        validate_mp4(path)

    print("[warmup] SUCCESS")


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        print(f"[warmup] FAILURE: {e}", file=sys.stderr)
        sys.exit(1)


