FROM runpod/worker-comfyui:5.7.1-base
SHELL ["/bin/bash", "-lc"]

# tools
RUN apt-get update && apt-get install -y git ffmpeg && rm -rf /var/lib/apt/lists/*

# --- pick the python env ComfyUI uses ---
ENV VENV_CANDIDATES="/opt/venv /workspace/venv /comfyui/.venv"
RUN for v in ${VENV_CANDIDATES}; do \
      if [ -x "${v}/bin/python" ]; then echo "export VENV_PY=${v}/bin/python" >> /etc/profile.d/venv.sh; break; fi; \
    done \
 && test -n "${VENV_PY:-}" || (echo "No venv python found" && exit 1)

# --- Install endpoint custom nodes ---
WORKDIR /comfyui/custom_nodes
RUN git clone https://github.com/chibiace/ComfyUI-Chibi-Nodes \
 && git clone https://github.com/chrisgoringe/cg-use-everywhere \
 && git clone https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite \
 && git clone https://github.com/pythongosssss/ComfyUI-Custom-Scripts \
 && git clone https://github.com/kijai/ComfyUI-WanVideoWrapper

# --- FP16 fix: FORCE torch 2.7 nightly cu124 ---
ARG PYTORCH_INDEX_URL=https://download.pytorch.org/whl/nightly/cu124
RUN source /etc/profile.d/venv.sh \
 && "${VENV_PY}" -m pip uninstall -y torch torchvision torchaudio || true \
 && "${VENV_PY}" -m pip install --no-cache-dir --force-reinstall --pre torch --index-url ${PYTORCH_INDEX_URL} \
 && "${VENV_PY}" -m pip install --no-cache-dir --force-reinstall --pre torchvision --index-url ${PYTORCH_INDEX_URL} --no-deps

# Verify
RUN source /etc/profile.d/venv.sh && "${VENV_PY}" - <<'EOF'
import torch
print("torch:", torch.__version__)
print("cuda:", torch.version.cuda)
assert torch.version.cuda == "12.4"
assert hasattr(torch.backends.cuda.matmul, "allow_fp16_accumulation")
print("OK")
EOF

# --- Override runtime scripts ---
WORKDIR /
COPY start.sh /start.sh
COPY handler.py /handler.py
COPY warmup.py /warmup.py
COPY comfy_client.py /comfy_client.py
COPY warmup_workflow.json /warmup_workflow.json
RUN chmod +x /start.sh

CMD ["/start.sh"]
