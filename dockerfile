# ===== Build-time configuration =====
# WebGUI service port and optional extra args for ComfyUI
ARG PORT=8188
ARG COMFYARG=""

# ===== Base image =====
FROM nvidia/cuda:12.4.0-base-ubuntu22.04

# Re-declare build args for use after FROM
ARG PORT
ARG COMFYARG

ENV docker_PORT=${PORT}
ENV docker_COMFYARG=${COMFYARG}

# ===== Base system setup =====
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update -y --fix-missing \
  && apt-get install -y \
    apt-utils \
    locales \
    ca-certificates \
  && apt-get upgrade -y \
  && apt-get clean

# UTF-8 locale
RUN localedef -i en_US -c -f UTF-8 -A /usr/share/locale/locale.alias en_US.UTF-8
ENV LANG=en_US.utf8
ENV LC_ALL=C

# Core tools and Python
RUN apt-get update -y --fix-missing \
  && apt-get upgrade -y \
  && apt-get install -y \
    build-essential \
    python3-dev \
    python3-venv \
    python3-pip \
    python-is-python3 \
    unzip \
    wget \
    zip \
    zlib1g \
    zlib1g-dev \
    gnupg \
    rsync \
    git \
    sudo \
    libglib2.0-0 \
    socat \
  && apt-get clean

# GL/Vulkan bits needed for ComfyUI / OpenCV
RUN apt-get update -y --fix-missing \
  && apt-get install -y \
    libglvnd0 \
    libglvnd-dev \
    libegl1-mesa-dev \
    libvulkan1 \
    libvulkan-dev \
    ffmpeg \
    libgl1-mesa-glx \
    libglib2.0-0 \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/* \
  && mkdir -p /usr/share/glvnd/egl_vendor.d \
  && echo '{"file_format_version":"1.0.0","ICD":{"library_path":"libEGL_nvidia.so.0"}}' > /usr/share/glvnd/egl_vendor.d/10_nvidia.json \
  && mkdir -p /usr/share/vulkan/icd.d \
  && echo '{"file_format_version":"1.0.0","ICD":{"library_path":"libGLX_nvidia.so.0","api_version":"1.3"}}' > /usr/share/vulkan/icd.d/nvidia_icd.json

ENV MESA_D3D12_DEFAULT_ADAPTER_NAME="NVIDIA"

# ===== Create TrueNAS "apps"-style user =====
# You said apps is UID/GID 568; this assumes your SCALE box uses that.
RUN groupadd -g 568 apps \
  && useradd -u 568 -g 568 -m -s /bin/bash appuser \
  && rm -rf /var/lib/apt/lists/*

# ===== Entrypoint script =====
COPY entrypoint.sh /entrypoint.sh

# Fix potential CRLF and make executable
RUN sed -i 's/\r$//' /entrypoint.sh \
  && chmod +x /entrypoint.sh

# Switch to non-root app user (apps:apps -> 568:568)
USER 568:568

# Make ~/.local/bin available on PATH
ENV PATH=/home/appuser/.local/bin:$PATH

# ===== ComfyUI setup =====
WORKDIR /app

# Clone ComfyUI (specific version)
RUN git clone https://github.com/comfyanonymous/ComfyUI.git --branch v0.3.57

WORKDIR /app/ComfyUI

# Create and activate venv
RUN python3 -m venv .venv --prompt "ComfyUI"
ENV PATH="/app/ComfyUI/.venv/bin:$PATH"

# Install PyTorch (cu118) and dependencies
# (Version choice as in your original Dockerfile)
RUN pip install torch==2.7.1 torchvision==0.22.1 torchaudio==2.7.1 --index-url https://download.pytorch.org/whl/cu118

# install ComfyUI dependencies + GitPython
RUN pip install --no-cache-dir -r requirements.txt gitpython toml \
  && pip cache purge

# ===== Networking / runtime =====
EXPOSE ${PORT}

ENTRYPOINT ["/entrypoint.sh"]

CMD python /app/ComfyUI/main.py --listen 0.0.0.0 --port "${docker_PORT}" ${docker_COMFYARG}
