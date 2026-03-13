#!/usr/bin/env bash

set -euo pipefail

# Installs NVIDIA Container Toolkit on Ubuntu 25.04 for Docker Engine.
# Includes rootless-friendly guidance and verification commands.

if [[ ! -f /etc/os-release ]]; then
  echo "Cannot detect OS (missing /etc/os-release)."
  exit 1
fi

# shellcheck disable=SC1091
source /etc/os-release
if [[ "${ID:-}" != "ubuntu" ]]; then
  echo "This script is intended for Ubuntu. Detected ID=${ID:-unknown}."
  exit 1
fi

echo "==> Adding NVIDIA Container Toolkit repository"
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey |
  sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg

curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list |
  sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' |
  sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list >/dev/null

# NVIDIA docs omit sudo here in some snippets; keep sudo for system file edit.
sudo sed -i -e '/experimental/ s/^#//g' /etc/apt/sources.list.d/nvidia-container-toolkit.list

echo "==> Installing NVIDIA Container Toolkit"
sudo apt-get update
sudo apt-get install -y nvidia-container-toolkit

echo "==> Configuring Docker runtime with nvidia-ctk"
sudo nvidia-ctk runtime configure --runtime=docker

echo "==> Restarting Docker services where available"
if systemctl is-active --quiet docker; then
  sudo systemctl restart docker
fi

if systemctl --user is-active --quiet docker; then
  systemctl --user restart docker
fi

echo ""
echo "==> Installation complete. Verification:"
echo "    which nvidia-ctk && nvidia-ctk --version"
echo "    docker info | grep -i -E 'rootless|runtimes|nvidia'"
echo "    docker run --rm --gpus all nvidia/cuda:12.3.2-base-ubuntu22.04 nvidia-smi"
