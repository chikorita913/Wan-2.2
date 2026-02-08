FROM runpod/worker-comfyui:5.7.1-base

SHELL ["/bin/bash", "-lc"]

# --- Tools you wanted ---
RUN apt-get update && apt-get install -y --no-install-recommends \
    git ffmpeg \
 && rm -rf /var/lib/apt/lists/*

# --- Pick the python env ComfyUI runs with ---
# We write VENV_PY into /etc/profile.d/venv.sh so later RUNs can source it.
ENV VENV_CANDIDATES="/opt/venv /workspace/venv /comfyui/.venv"
RUN set -euxo pipefail; \
    rm -f /etc/profile.d/venv.sh; \
    for v in ${VENV_CANDIDATES}; do \
      if [ -x "${v}/bin/python" ]; then \
        echo "export VENV_PY=${v}/bin/python" >> /etc/profile.d/venv.sh; \
        echo "export PATH=${v}/bin:\$PATH" >> /etc/profile.d/venv.sh; \
        break; \
      fi; \
    done; \
    source /etc/profile.d/venv.sh; \
    test -n "${VENV_PY:-}" || (echo "No venv python found in ${VENV_CANDIDATES}" && exit 1); \
    "${VENV_PY}" -V

# --- Custom nodes (your exact clones) ---
WORKDIR /comfyui/custom_nodes
RUN git clone https://github.com/chibiace/ComfyUI-Chibi-Nodes \
 && git clone https://github.com/chrisgoringe/cg-use-everywhere \
 && git clone https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite \
 && git clone https://github.com/pythongosssss/ComfyUI-Custom-Scripts \
 && git clone https://github.com/kijai/ComfyUI-WanVideoWrapper

# --- FP16 fix + Torch/TorchVision/TorchAudio nightly pin (Option A: SAME DATE) ---
# This avoids the exact conflict you pasted:
# torchvision dev build hard-depends on torch==same-date dev build.
ARG PYTORCH_INDEX_URL="https://download.pytorch.org/whl/nightly/cu124"
ARG TORCH_VER="2.7.0.dev20250226+cu124"
ARG TORCHVISION_VER="0.22.0.dev20250226+cu124"
ARG TORCHAUDIO_VER="2.7.0.dev20250226+cu124"

RUN set -euxo pipefail; \
    source /etc/profile.d/venv.sh; \
    "${VENV_PY}" -m pip install --no-cache-dir -U pip setuptools wheel; \
    "${VENV_PY}" -m pip uninstall -y torch torchvision torchaudio || true; \
    "${VENV_PY}" -m pip install --no-cache-dir --force-reinstall --pre \
        "torch==${TORCH_VER}" \
        "torchvision==${TORCHVISION_VER}" \
        "torchaudio==${TORCHAUDIO_VER}" \
        --index-url "${PYTORCH_INDEX_URL}"

# --- Verify the FP16 flag exists (this was the crash in WanVideoWrapper) ---
RUN set -euxo pipefail; \
    source /etc/profile.d/venv.sh; \
    "${VENV_PY}" - <<'PY'
import torch, torchvision
print("torch:", torch.__version__)
print("torchvision:", torchvision.__version__)
print("cuda:", torch.version.cuda)
assert hasattr(torch.backends.cuda.matmul, "allow_fp16_accumulation"), "allow_fp16_accumulation missing"
print("OK")
PY

# IMPORTANT:
# - DO NOT COPY start.sh / handler.py / etc.
# - DO NOT set CMD or ENTRYPOINT.
# The base image scripts will run as-is.
WORKDIR /
