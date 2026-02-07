FROM runpod/worker-comfyui:5.7.1-base

SHELL ["/bin/bash", "-lc"]

# --- Choose the SAME Python env ComfyUI runs with (covers /opt/venv OR /workspace/venv OR system) ---
ENV VENV_CANDIDATES="/opt/venv /workspace/venv /comfyui/.venv"
RUN for v in ${VENV_CANDIDATES}; do \
      if [ -x "${v}/bin/python" ]; then echo "export PATH=${v}/bin:\$PATH" >> /etc/profile.d/venv.sh; break; fi; \
    done
ENV PATH="/opt/venv/bin:/workspace/venv/bin:/comfyui/.venv/bin:${PATH}"

# mp4 validation
RUN apt-get update && apt-get install -y ffmpeg && rm -rf /var/lib/apt/lists/*

# --- Install endpoint custom nodes here (fill in) ---
# WORKDIR /comfyui/custom_nodes
# RUN git clone <CUSTOM_NODE_REPO_URL_1> \
#  && git clone <CUSTOM_NODE_REPO_URL_2> \
#  && true
WORKDIR /

# --- FP16 fix: FORCE torch 2.7 nightly cu124 (same as your manual fix) ---
ARG PYTORCH_INDEX_URL=https://download.pytorch.org/whl/nightly/cu124
RUN python -m pip uninstall -y torch torchvision torchaudio || true \
 && python -m pip install --no-cache-dir --force-reinstall --pre torch --index-url ${PYTORCH_INDEX_URL} \
 && python -m pip install --no-cache-dir --force-reinstall --pre torchvision --index-url ${PYTORCH_INDEX_URL} --no-deps

# Verify: must be cu124 + allow_fp16_accumulation exists
RUN python - <<'EOF'
import torch
print("torch:", torch.__version__)
print("cuda:", torch.version.cuda)
assert torch.version.cuda == "12.4"
assert hasattr(torch.backends.cuda.matmul, "allow_fp16_accumulation")
print("OK")
EOF

# --- Override runtime scripts (these will replace whatever the base image had) ---
COPY start.sh /start.sh
COPY handler.py /handler.py
COPY warmup.py /warmup.py
COPY comfy_client.py /comfy_client.py
COPY warmup_workflow.json /warmup_workflow.json

RUN chmod +x /start.sh

CMD ["/start.sh"]
