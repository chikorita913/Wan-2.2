# Keep RunPod’s base image (includes start.sh / handler / entrypoint behavior)
FROM runpod/worker-comfyui:5.7.1-base

SHELL ["/bin/bash", "-lc"]

# ------------------------------------------------------------
# System tools
# ------------------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    ffmpeg \
 && rm -rf /var/lib/apt/lists/*

# ------------------------------------------------------------
# Select the SAME Python venv ComfyUI actually uses
# ------------------------------------------------------------
ENV VENV_CANDIDATES="/opt/venv /workspace/venv /comfyui/.venv"

RUN set -euxo pipefail; \
    rm -f /etc/profile.d/venv.sh; \
    touch /etc/profile.d/venv.sh; \
    for v in ${VENV_CANDIDATES}; do \
      if [ -x "${v}/bin/python" ]; then \
        echo "export VENV_PY=${v}/bin/python" >> /etc/profile.d/venv.sh; \
        echo "export PATH=${v}/bin:\$PATH" >> /etc/profile.d/venv.sh; \
        break; \
      fi; \
    done; \
    source /etc/profile.d/venv.sh; \
    test -n "${VENV_PY:-}" || (echo "No venv python found" && exit 1); \
    "${VENV_PY}" -V

# ------------------------------------------------------------
# Base Python tooling
# ------------------------------------------------------------
RUN set -euxo pipefail; \
    source /etc/profile.d/venv.sh; \
    "${VENV_PY}" -m pip install --no-cache-dir -U pip setuptools wheel

# ------------------------------------------------------------
# Torch stack (CUDA-matched, torchaudio INCLUDED)
# ------------------------------------------------------------
RUN set -euxo pipefail; \
    source /etc/profile.d/venv.sh; \
    "${VENV_PY}" -m pip uninstall -y torch torchvision torchaudio || true; \
    "${VENV_PY}" -m pip install --no-cache-dir \
      torch==2.10.0+cu128 \
      torchvision==0.25.0+cu128 \
      torchaudio==2.10.0 \
      --index-url https://download.pytorch.org/whl/cu128; \
    "${VENV_PY}" - <<'PY'
import torch, torchvision, torchaudio
print("torch:", torch.__version__)
print("torchvision:", torchvision.__version__)
print("torchaudio:", torchaudio.__version__)
print("cuda (wheel):", torch.version.cuda)
assert hasattr(torch.backends.cuda.matmul, "allow_fp16_accumulation")
print("OK: FP16 accumulation present")
PY

# ------------------------------------------------------------
# Custom nodes
# ------------------------------------------------------------
WORKDIR /comfyui/custom_nodes

RUN set -euxo pipefail; \
    git clone https://github.com/chibiace/ComfyUI-Chibi-Nodes; \
    git clone https://github.com/chrisgoringe/cg-use-everywhere; \
    git clone https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite; \
    git clone https://github.com/pythongosssss/ComfyUI-Custom-Scripts; \
    git clone https://github.com/kijai/ComfyUI-WanVideoWrapper; \
    git clone https://github.com/Fannovel16/ComfyUI-Frame-Interpolation

# ------------------------------------------------------------
# Install ALL custom-node requirements into the SAME venv
# BUT: for ComfyUI-Frame-Interpolation, force NO-CUPY requirements
# ------------------------------------------------------------
RUN set -euxo pipefail; \
    source /etc/profile.d/venv.sh; \
    \
    # 1) Install requirements*.txt for all nodes, except the VFI node's cupy/alt files
    for r in /comfyui/custom_nodes/*/requirements*.txt; do \
      if [ -f "$r" ]; then \
        case "$r" in \
          /comfyui/custom_nodes/ComfyUI-Frame-Interpolation/requirements-with-cupy.txt|\
          /comfyui/custom_nodes/ComfyUI-Frame-Interpolation/requirements.txt) \
            echo "Skipping VFI requirements file (will install no-cupy instead): $r" ;; \
          *) \
            echo "Installing $r"; \
            "${VENV_PY}" -m pip install --no-cache-dir -r "$r" ;; \
        esac; \
      fi; \
    done; \
    \
    # 2) Install requirements/*.txt folders (unchanged behavior)
    for d in /comfyui/custom_nodes/*/requirements; do \
      if [ -d "$d" ]; then \
        while IFS= read -r -d '' f; do \
          echo "Installing $f"; \
          "${VENV_PY}" -m pip install --no-cache-dir -r "$f"; \
        done < <(find "$d" -maxdepth 1 -type f -name '*.txt' -print0); \
      fi; \
    done; \
    \
    # 3) Force install NO-CUPY deps for ComfyUI-Frame-Interpolation
    VFI_NO_CUPY="/comfyui/custom_nodes/ComfyUI-Frame-Interpolation/requirements-no-cupy.txt"; \
    test -f "$VFI_NO_CUPY" || (echo "Missing $VFI_NO_CUPY" && exit 1); \
    echo "Installing VFI NO-CUPY deps: $VFI_NO_CUPY"; \
    "${VENV_PY}" -m pip install --no-cache-dir -r "$VFI_NO_CUPY"

# ------------------------------------------------------------
# IMPORTANT: Do NOT override RunPod runtime scripts
# ------------------------------------------------------------
WORKDIR /comfyui
COPY handler.py /handler.py
COPY start.sh /start.sh
RUN chmod +x /start.sh
