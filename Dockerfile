# ---- Base: CUDA 12.4 runtime (good for cu124 nightlies) ----
FROM nvidia/cuda:12.4.1-cudnn-runtime-ubuntu22.04

ENV DEBIAN_FRONTEND=noninteractive \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

# ---- System deps ----
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl wget git \
    python3 python3-venv python3-pip \
    build-essential pkg-config \
    libgl1 libglib2.0-0 \
 && rm -rf /var/lib/apt/lists/*

# ---- Virtualenv ----
ENV VENV_DIR=/opt/venv
RUN python3 -m venv ${VENV_DIR}
ENV PATH="${VENV_DIR}/bin:${PATH}"
ENV VENV_PY="${VENV_DIR}/bin/python"

# Upgrade pip tooling
RUN "${VENV_PY}" -m pip install --no-cache-dir -U pip setuptools wheel

# ---- PINNED PyTorch nightlies (Option A) ----
# Pick ONE nightly date and pin torch/vision/audio to the *same* date.
# This avoids the exact conflict you saw (vision dev build hard-pins torch==same-date).
ARG PYTORCH_INDEX_URL=https://download.pytorch.org/whl/nightly/cu124
ARG TORCH_VER=2.7.0.dev20250226+cu124
ARG TORCHVISION_VER=0.22.0.dev20250226+cu124
ARG TORCHAUDIO_VER=2.7.0.dev20250226+cu124

RUN "${VENV_PY}" -m pip uninstall -y torch torchvision torchaudio || true \
 && "${VENV_PY}" -m pip install --no-cache-dir --force-reinstall --pre \
      "torch==${TORCH_VER}" \
      "torchvision==${TORCHVISION_VER}" \
      "torchaudio==${TORCHAUDIO_VER}" \
      --index-url "${PYTORCH_INDEX_URL}" \
 && "${VENV_PY}" - <<'PY'
import torch, torchvision
print("torch:", torch.__version__)
print("torchvision:", torchvision.__version__)
print("has allow_fp16_accumulation:",
      hasattr(torch.backends.cuda.matmul, "allow_fp16_accumulation"))
PY

# ---- ComfyUI ----
WORKDIR /workspace/runpod-slim

# Clone ComfyUI (pin to a commit if you want fully reproducible builds)
RUN git clone https://github.com/comfyanonymous/ComfyUI.git

# Install ComfyUI python deps
RUN "${VENV_PY}" -m pip install --no-cache-dir -r /workspace/runpod-slim/ComfyUI/requirements.txt

# (Optional) comfy-cli if you use `comfy` commands (model download, etc.)
RUN "${VENV_PY}" -m pip install --no-cache-dir -U comfy-cli

# ---- Custom nodes (optional: add your own clones here) ----
# Example (keep commented; add the nodes you actually want)
# RUN git clone https://github.com/<you>/<node>.git /workspace/runpod-slim/ComfyUI/custom_nodes/<node>

# Install any custom node requirements if you have them.
# IMPORTANT: do this AFTER torch is pinned, so node deps don’t drag torch around.
# RUN find /workspace/runpod-slim/ComfyUI/custom_nodes -maxdepth 2 -name "requirements.txt" -print -exec "${VENV_PY}" -m pip install --no-cache-dir -r {} \;

# ---- Start script ----
# If you already have a start.sh in your repo, COPY it in.
# Otherwise, here’s a simple default that starts ComfyUI.
COPY start.sh /start.sh
RUN chmod +x /start.sh

EXPOSE 8188
CMD ["/bin/bash", "-lc", "/start.sh"]
