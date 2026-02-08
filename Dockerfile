# Keep RunPod’s base image (includes the base start.sh / handler / entrypoint behavior)
FROM runpod/worker-comfyui:5.7.1-base

SHELL ["/bin/bash", "-lc"]

# --- tools you actually need for your nodes/workflows ---
RUN apt-get update && apt-get install -y --no-install-recommends \
    git ffmpeg \
 && rm -rf /var/lib/apt/lists/*

# --- Choose the SAME Python env ComfyUI runs with (covers /opt/venv OR /workspace/venv OR /comfyui/.venv) ---
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
    test -n "${VENV_PY:-}" || (echo "No venv python found in: ${VENV_CANDIDATES}" && exit 1); \
    "${VENV_PY}" -V

# --- FP16 fix: install latest PyTorch nightly cu124 (NO date pin, avoids wheel rotation breakage) ---
ARG PYTORCH_INDEX_URL=https://download.pytorch.org/whl/nightly/cu124
RUN set -euxo pipefail; \
    source /etc/profile.d/venv.sh; \
    "${VENV_PY}" -m pip install --no-cache-dir -U pip setuptools wheel; \
    "${VENV_PY}" -m pip uninstall -y torch torchvision torchaudio || true; \
    "${VENV_PY}" -m pip install --no-cache-dir --pre \
      --index-url "${PYTORCH_INDEX_URL}" \
      torch torchvision torchaudio; \
    "${VENV_PY}" - <<'PY'
import torch
import torchvision
import torchaudio
print("torch:", torch.__version__)
print("torchvision:", torchvision.__version__)
print("torchaudio:", torchaudio.__version__)
print("cuda:", torch.version.cuda)
assert hasattr(torch.backends.cuda.matmul, "allow_fp16_accumulation"), "missing allow_fp16_accumulation"
print("OK: allow_fp16_accumulation present")
PY

# --- Custom nodes (your original clones) ---
WORKDIR /comfyui/custom_nodes
RUN set -euxo pipefail; \
    git clone https://github.com/chibiace/ComfyUI-Chibi-Nodes; \
    git clone https://github.com/chrisgoringe/cg-use-everywhere; \
    git clone https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite; \
    git clone https://github.com/pythongosssss/ComfyUI-Custom-Scripts; \
    git clone https://github.com/kijai/ComfyUI-WanVideoWrapper

# --- Install ALL custom node requirements into the SAME venv ComfyUI uses (STRICT) ---
RUN set -euxo pipefail; \
    source /etc/profile.d/venv.sh; \
    for r in /comfyui/custom_nodes/*/requirements*.txt; do \
      if [ -f "$r" ]; then \
        echo "Installing $r"; \
        "${VENV_PY}" -m pip install --no-cache-dir -r "$r"; \
      fi; \
    done; \
    for d in /comfyui/custom_nodes/*/requirements; do \
      if [ -d "$d" ]; then \
        while IFS= read -r -d '' f; do \
          echo "Installing $f"; \
          "${VENV_PY}" -m pip install --no-cache-dir -r "$f"; \
        done < <(find "$d" -maxdepth 1 -type f -name '*.txt' -print0); \
      fi; \
    done

# --- IMPORTANT: Do NOT override RunPod base runtime scripts ---
# (No COPY start.sh, no COPY handler.py, no CMD/ENTRYPOINT here.)
WORKDIR /comfyui
