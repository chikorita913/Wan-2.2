#!/usr/bin/env bash
set -euo pipefail

############################
# Link persistent models
############################
SRC="/runpod-volume/runpod-slim/ComfyUI/models"
DST="/comfyui/models"

echo "[models] linking $DST -> $SRC"

# safety check
if [ ! -d "$SRC" ]; then
  echo "[ERROR] Missing source directory: $SRC"
  ls -lah /runpod-volume || true
  exit 1
fi

# remove whatever exists at destination
if [ -e "$DST" ] || [ -L "$DST" ]; then
  rm -rf "$DST"
fi

# create symlink
ln -s "$SRC" "$DST"

# verify
echo "[models] resolved path:"
readlink -f "$DST"

echo "[models] contents:"
ls -lah "$DST" | head -n 50

echo "[models] done ✅"

############################
# Original start script
############################

# Use libtcmalloc for better memory management
TCMALLOC="$(ldconfig -p | grep -Po "libtcmalloc.so.\d" | head -n 1)"
export LD_PRELOAD="${TCMALLOC}"

# Ensure ComfyUI-Manager runs in offline network mode inside the container
comfy-manager-set-mode offline || echo "worker-comfyui - Could not set ComfyUI-Manager network_mode" >&2

echo "worker-comfyui: Starting ComfyUI"

# Allow operators to tweak verbosity; default is DEBUG.
: "${COMFY_LOG_LEVEL:=DEBUG}"

# Serve the API and don't shutdown the container
if [ "$SERVE_API_LOCALLY" == "true" ]; then
    python -u /comfyui/main.py \
      --disable-auto-launch \
      --disable-metadata \
      --listen \
      --verbose "${COMFY_LOG_LEVEL}" \
      --log-stdout &

    echo "worker-comfyui: Starting RunPod Handler"
    python -u /handler.py --rp_serve_api --rp_api_host=0.0.0.0
else
    python -u /comfyui/main.py \
      --disable-auto-launch \
      --disable-metadata \
      --verbose "${COMFY_LOG_LEVEL}" \
      --log-stdout &

    echo "worker-comfyui: Starting RunPod Handler"
    python -u /handler.py
fi
