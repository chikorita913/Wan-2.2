# Use RunPod’s ComfyUI worker base so we keep their built-in start.sh / handler behavior
FROM runpod/worker-comfyui:5.7.1-base

ENV DEBIAN_FRONTEND=noninteractive \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

# ---- Pin PyTorch nightlies (CUDA 12.4) ----
# IMPORTANT: torch/vision/audio must be the SAME nightly date to avoid pip conflicts.
ARG PYTORCH_INDEX_URL="https://download.pytorch.org/whl/nightly/cu124"
ARG TORCH_VER="2.7.0.dev20250226+cu124"
ARG TORCHVISION_VER="0.22.0.dev20250226+cu124"
ARG TORCHAUDIO_VER="2.7.0.dev20250226+cu124"

# RunPod base images typically provide a venv and VENV_PY env var.
# We defensively fallback to /opt/venv/bin/python if VENV_PY is not set.
SHELL ["/bin/bash", "-lc"]

RUN set -euxo pipefail; \
    VPY="${VENV_PY:-/opt/venv/bin/python}"; \
    "$VPY" -m pip install --no-cache-dir -U pip setuptools wheel; \
    "$VPY" -m pip uninstall -y torch torchvision torchaudio || true; \
    "$VPY" -m pip install --no-cache-dir --force-reinstall --pre \
        "torch==${TORCH_VER}" \
        "torchvision==${TORCHVISION_VER}" \
        "torchaudio==${TORCHAUDIO_VER}" \
        --index-url "${PYTORCH_INDEX_URL}"; \
    "$VPY" - <<'PY' \
import torch, torchvision \
print("torch:", torch.__version__) \
print("torchvision:", torchvision.__version__) \
print("has allow_fp16_accumulation:", hasattr(torch.backends.cuda.matmul, "allow_fp16_accumulation")) \
PY

# ---- (Optional) If you want to bake in extra OS deps, do it here ----
# RUN apt-get update && apt-get install -y --no-install-recommends <stuff> && rm -rf /var/lib/apt/lists/*

# ---- (Optional) If you want to bake in custom nodes, do it here ----
# WORKDIR /workspace/runpod-slim/ComfyUI/custom_nodes
# RUN git clone https://github.com/<author>/<repo>.git
# RUN "${VENV_PY:-/opt/venv/bin/python}" -m pip install --no-cache-dir -r /workspace/runpod-slim/ComfyUI/custom_nodes/<repo>/requirements.txt

# DO NOT copy or override start.sh
# DO NOT set CMD or ENTRYPOINT
# The base image will keep starting ComfyUI the same way it already does.
