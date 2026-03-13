#!/usr/bin/env bash

set -euo pipefail

# Installs Docker Engine on Ubuntu 25.04 and configures Docker in rootless mode.
# Also removes incompatible Docker distributions (snap docker and docker-desktop).

if [[ "$(id -u)" -eq 0 ]]; then
  echo "Please run this script as a regular user (not root)."
  exit 1
fi

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

echo "==> Removing incompatible Docker distributions if present"
if command -v snap >/dev/null 2>&1 && snap list 2>/dev/null | awk '{print $1}' | grep -qx docker; then
  sudo snap remove docker
fi

if dpkg -l 2>/dev/null | grep -qi '^ii\s\+docker-desktop\s'; then
  sudo apt-get remove -y docker-desktop
fi

echo "==> Installing prerequisites"
sudo apt-get update
sudo apt-get install -y ca-certificates curl uidmap dbus-user-session slirp4netns fuse-overlayfs

echo "==> Setting up Docker APT repository"
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  ${VERSION_CODENAME} stable" |
  sudo tee /etc/apt/sources.list.d/docker.list >/dev/null

sudo apt-get update

echo "==> Installing Docker Engine"
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin docker-ce-rootless-extras

echo "==> Disabling rootful Docker daemon to avoid conflicts"
sudo systemctl disable --now docker.service docker.socket || true
sudo systemctl disable --now containerd.service || true

echo "==> Configuring rootless Docker for user: ${USER}"
if ! command -v dockerd-rootless-setuptool.sh >/dev/null 2>&1; then
  echo "dockerd-rootless-setuptool.sh not found; expected from docker-ce-rootless-extras."
  exit 1
fi

dockerd-rootless-setuptool.sh install

echo "==> Enabling lingering so user services survive logout"
sudo loginctl enable-linger "${USER}"

echo "==> Ensuring Docker user service is enabled"
systemctl --user daemon-reload
systemctl --user enable --now docker

echo "==> Persisting DOCKER_HOST for rootless Docker"
if ! grep -q 'DOCKER_HOST=unix:///run/user/$(id -u)/docker.sock' "${HOME}/.zshrc" 2>/dev/null; then
  {
    echo ''
    echo '# Rootless Docker'
    echo 'export DOCKER_HOST=unix:///run/user/$(id -u)/docker.sock'
  } >> "${HOME}/.zshrc"
fi

export DOCKER_HOST="unix:///run/user/$(id -u)/docker.sock"

echo ""
echo "==> Installation complete. Verification:"
echo "    docker info | grep -i -E 'rootless|server version|docker root dir'"
echo "    ps -o pid,user,uid,comm -C dockerd"
echo ""
echo "Open a new shell (or run: source ~/.zshrc) before regular use."
