FROM runpod/worker-comfyui:5.7.1-base
SHELL ["/bin/bash", "-lc"]

# Tools (git for clones, ffmpeg for ffprobe mp4 validation)
RUN apt-get update && apt-get install -y git ffmpeg && rm -rf /var/lib/apt/lists/*

# Use the same Python env ComfyUI runs with (prefer /opt/venv; fall back if needed)
ENV VENV_CANDIDATES="/opt/venv /workspace/venv /comfyui/.venv"
RUN for v in ${VENV_CANDIDATES}; do \
      if [ -x "${v}/bin/python" ]; then echo "export VENV_PY=${v}/bin/python" > /etc/profile.d/venv.sh; break; fi; \
    done \
 && source /etc/profile.d/venv.sh \
 && test -n "${VENV_PY:-}" || (echo "No venv python found" && exit 1)

# Prove which python we will use (must match ComfyUI runtime env)
RUN source /etc/profile.d/venv.sh \
 && "${VENV_PY}" -c "import sys; print('python:', sys.executable)"

# --- Install endpoint custom nodes ---
WORKDIR /comfyui/custom_nodes
RUN git clone https://github.com/chibiace/ComfyUI-Chibi-Nodes \
 && git clone https://github.com/chrisgoringe/cg-use-everywhere \
 && git clone https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite \
 && git clone https://github.com/pythongosssss/ComfyUI-Custom-Scripts \
 && git clone https://github.com/kijai/ComfyUI-WanVideoWrapper

# --- Install ALL custom node requirements into the SAME venv ComfyUI uses (STRICT) ---
RUN source /etc/profile.d/venv.sh \
 && for r in /comfyui/custom_nodes/*/requirements*.txt; do \
      if [ -f "$r" ]; then \
        echo "Installing $r"; \
        "${VENV_PY}" -m pip install --no-cache-dir -r "$r"; \
      fi; \
    done \
 && for d in /comfyui/custom_nodes/*/requirements; do \
      if [ -d "$d" ]; then \
        while IFS= read -r -d '' f; do \
          echo "Installing $f"; \
          "${VENV_PY}" -m pip install --no-cache-dir -r "$f"; \
        done < <(find "$d" -maxdepth 1 -type f -name '*.txt' -print0); \
      fi; \
    done

# --- FP16 + WanVideoWrapper fix: FORCE torch/torchvision/torchaudio 2.7 nightly cu124 ---
ARG PYTORCH_INDEX_URL=https://download.pytorch.org/whl/nightly/cu124
RUN source /etc/profile.d/venv.sh \
 && "${VENV_PY}" -m pip uninstall -y torch torchvision torchaudio || true \
 && "${VENV_PY}" -m pip install --no-cache-dir --force-reinstall --pre \
      torch torchvision torchaudio \
      --index-url ${PYTORCH_INDEX_URL}

# Verify: must be cu124 + allow_fp16_accumulation exists + torchaudio imports
RUN source /etc/profile.d/venv.sh && "${VENV_PY}" - <<'EOF'
import torch, torchvision, torchaudio
print("torch:", torch.__version__)
print("torchvision:", torchvision.__version__)
print("torchaudio:", torchaudio.__version__)
print("cuda:", torch.version.cuda)
assert torch.version.cuda == "12.4"
assert hasattr(torch.backends.cuda.matmul, "allow_fp16_accumulation")
print("OK")
EOF

# IMPORTANT:
# - No COPY of start.sh/handler.py
# - No CMD override
# Base image will run the default RunPod ComfyUI worker.
