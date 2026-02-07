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
 && which python \
 && python -c "import sys; print(sys.executable)"

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

# --- FP16 fix: FORCE torch 2.7 nightly cu124 (same as manual fix) ---
ARG PYTORCH_INDEX_URL=https://download.pytorch.org/whl/nightly/cu124
RUN source /etc/profile.d/venv.sh \
 && "${VENV_PY}" -m pip uninstall -y torch torchvision torchaudio || true \
 && "${VENV_PY}" -m pip install --no-cache-dir --force-reinstall --pre torch --index-url ${PYTORCH_INDEX_URL} \
 && "${VENV_PY}" -m pip install --no-cache-dir --force-reinstall --pre torchvision --index-url ${PYTORCH_INDEX_URL} --no-deps

# Verify: must be cu124 + allow_fp16_accumulation exists
RUN source /etc/profile.d/venv.sh && "${VENV_PY}" - <<'EOF'
import torch
print("torch:", torch.__version__)
print("cuda:", torch.version.cuda)
assert torch.version.cuda == "12.4"
assert hasattr(torch.backends.cuda.matmul, "allow_fp16_accumulation")
print("OK")
EOF

# --- Override runtime scripts (repo-root files) ---
WORKDIR /
COPY start.sh /start.sh
COPY handler.py /handler.py
COPY warmup.py /warmup.py
COPY comfy_client.py /comfy_client.py
COPY warmup_workflow.json /warmup_workflow.json

RUN chmod +x /start.sh
CMD ["/start.sh"]
