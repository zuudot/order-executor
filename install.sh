#!/usr/bin/env bash
# Ensure Docker is available, then pull the official order-executor image.
#
# Usage:
#   ./install.sh                 # pull zuudot/order-executor:latest
#   ./install.sh 0.1.3           # pull zuudot/order-executor:0.1.3
#   ORDER_EXECUTOR_IMAGE=zuudot/order-executor:0.1.3 ./install.sh
#
# Or:
#   curl -fsSL https://raw.githubusercontent.com/zuudot/order-executor/main/install.sh | bash

set -euo pipefail

REPO="${ORDER_EXECUTOR_REPO:-zuudot/order-executor}"
IMAGE_NAME="${ORDER_EXECUTOR_IMAGE_NAME:-zuudot/order-executor}"
CONFIG_DIR="${CONFIG_DIR:-./conf}"
RAW_BASE="https://raw.githubusercontent.com/${REPO}/main"

tag="${1:-latest}"
tag="${tag#v}"
IMAGE="${ORDER_EXECUTOR_IMAGE:-${IMAGE_NAME}:${tag}}"

need() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "error: '$1' is required" >&2
    exit 1
  }
}

need curl
need uname

os="$(uname -s | tr '[:upper:]' '[:lower:]')"
case "$os" in
  linux|darwin) ;;
  *)
    echo "error: unsupported OS '$os' (supported: linux, macOS)" >&2
    exit 1
    ;;
esac

DOCKER=(docker)

docker_daemon_ok() {
  "${DOCKER[@]}" info >/dev/null 2>&1
}

resolve_docker() {
  if command -v docker >/dev/null 2>&1; then
    DOCKER=(docker)
    if docker_daemon_ok; then
      return 0
    fi
    if command -v sudo >/dev/null 2>&1 && sudo docker info >/dev/null 2>&1; then
      DOCKER=(sudo docker)
      return 0
    fi
    echo "error: Docker is installed but the daemon is not running." >&2
    if [[ "$os" == "darwin" ]]; then
      echo "       Open Docker Desktop, wait until it is running, then re-run this script." >&2
    else
      echo "       Start it with: sudo systemctl start docker" >&2
    fi
    exit 1
  fi
  return 1
}

install_docker_linux() {
  echo "Docker not found. Installing Docker Engine..."
  tmp="$(mktemp)"
  curl -fsSL https://get.docker.com -o "$tmp"
  if [[ "$(id -u)" -eq 0 ]]; then
    sh "$tmp"
    systemctl enable --now docker 2>/dev/null || service docker start 2>/dev/null || true
  else
    need sudo
    sudo sh "$tmp"
    sudo systemctl enable --now docker 2>/dev/null || sudo service docker start 2>/dev/null || true
    sudo usermod -aG docker "$USER" 2>/dev/null || true
  fi
  rm -f "$tmp"
}

install_docker_macos() {
  echo "Docker not found. Installing Docker Desktop..."
  if ! command -v brew >/dev/null 2>&1; then
    echo "error: Homebrew is not installed." >&2
    echo "       Install Docker Desktop from https://docs.docker.com/desktop/setup/install/mac-install/" >&2
    echo "       then re-run this script." >&2
    exit 1
  fi
  brew install --cask docker
  open -a Docker 2>/dev/null || true
  echo "Waiting for Docker Desktop to start..."
  for _ in $(seq 1 45); do
    if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
  done
  echo "error: Docker Desktop is installed but not ready yet." >&2
  echo "       Open Docker Desktop, wait until it is running, then re-run this script." >&2
  exit 1
}

ensure_docker() {
  if resolve_docker; then
    echo "Using Docker: ${DOCKER[*]}"
    return 0
  fi
  case "$os" in
    linux) install_docker_linux ;;
    darwin) install_docker_macos ;;
  esac
  if ! resolve_docker; then
    echo "error: Docker was installed, but this session cannot talk to the daemon yet." >&2
    if [[ "$os" == "linux" ]]; then
      echo "       Log out and back in (or run: newgrp docker), then re-run this script." >&2
    fi
    exit 1
  fi
}

compose() {
  if "${DOCKER[@]}" compose version >/dev/null 2>&1; then
    "${DOCKER[@]}" compose "$@"
  elif command -v docker-compose >/dev/null 2>&1; then
    docker-compose "$@"
  else
    echo "error: Docker Compose is not available." >&2
    echo "       Install the Compose plugin, then re-run this script." >&2
    exit 1
  fi
}

fetch_if_missing() {
  local dest="$1"
  local path="$2"
  if [[ -f "$dest" ]]; then
    return 0
  fi
  mkdir -p "$(dirname "$dest")"
  echo "Downloading ${path}"
  curl -fsSL "${RAW_BASE}/${path}" -o "$dest"
}

ensure_docker

echo "Pulling ${IMAGE}"
"${DOCKER[@]}" pull "$IMAGE"

fetch_if_missing ./docker-compose.yml docker-compose.yml
mkdir -p "$CONFIG_DIR"
fetch_if_missing "${CONFIG_DIR}/config.example.toml" conf/config.example.toml

if [[ ! -f "${CONFIG_DIR}/config.toml" ]]; then
  cp "${CONFIG_DIR}/config.example.toml" "${CONFIG_DIR}/config.toml"
  chmod 600 "${CONFIG_DIR}/config.toml"
  echo "Created ${CONFIG_DIR}/config.toml — edit this file before starting."
fi

cat > .env <<EOF
ORDER_EXECUTOR_IMAGE=${IMAGE}
EOF

echo "Image ready: ${IMAGE}"
echo "Start with:"
echo "  1. Edit ${CONFIG_DIR}/config.toml"
echo "  2. ${DOCKER[*]} compose up -d"
echo "  3. ${DOCKER[*]} compose logs -f"
