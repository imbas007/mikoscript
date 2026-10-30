#!/usr/bin/env bash
# getdocker.sh - Install Docker CE (official repo) on Kali / Debian / Ubuntu
# Supports: amd64, arm64, armhf
#
# Usage:
#   bash getdocker.sh                      # auto-detect
#   DOCKER_CODENAME=trixie bash getdocker.sh   # force a Debian/Ubuntu codename
#   SKIP_TEST=1 bash getdocker.sh          # skip hello-world test

set -euo pipefail

# ---------- helpers ----------
c_info()  { printf '\033[1;34m[*]\033[0m %s\n' "$*"; }
c_ok()    { printf '\033[1;32m[+]\033[0m %s\n' "$*"; }
c_warn()  { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }
c_err()   { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; exit 1; }

if [ "$(id -u)" -eq 0 ]; then
    SUDO=""
    TARGET_USER="${SUDO_USER:-root}"
else
    command -v sudo >/dev/null 2>&1 || c_err "sudo not found. Run as root or install sudo."
    SUDO="sudo"
    TARGET_USER="$USER"
fi

# ---------- detect OS ----------
[ -r /etc/os-release ] || c_err "/etc/os-release not found. Unsupported OS."
# shellcheck disable=SC1091
. /etc/os-release

OS_ID="${ID:-unknown}"
case "$OS_ID" in
    kali)
        DOCKER_DISTRO="debian"
        # Kali reports "kali-rolling", which Docker's repo does not have.
        # Docker's own docs say to use the Debian bookworm repo for Kali.
        CODENAME="${DOCKER_CODENAME:-bookworm}"
        ;;
    debian|raspbian)
        DOCKER_DISTRO="debian"
        CODENAME="${DOCKER_CODENAME:-${VERSION_CODENAME:-}}"
        ;;
    ubuntu|linuxmint|pop)
        DOCKER_DISTRO="ubuntu"
        CODENAME="${DOCKER_CODENAME:-${UBUNTU_CODENAME:-${VERSION_CODENAME:-}}}"
        ;;
    *)
        c_err "Unsupported distro: $OS_ID (supported: kali, debian, ubuntu)"
        ;;
esac
[ -n "$CODENAME" ] || c_err "Could not detect release codename. Set DOCKER_CODENAME manually."

# ---------- detect arch ----------
ARCH="$(dpkg --print-architecture)"
case "$ARCH" in
    amd64|arm64|armhf) ;;
    *) c_err "Architecture '$ARCH' is not supported by Docker CE packages." ;;
esac

c_info "OS: ${PRETTY_NAME:-$OS_ID} | Arch: $ARCH | Docker repo: $DOCKER_DISTRO/$CODENAME"

# ---------- remove conflicting packages ----------
c_info "Removing old/conflicting Docker packages (if any)..."
for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do
    if dpkg -s "$pkg" >/dev/null 2>&1; then
        $SUDO apt-get remove -y "$pkg"
    fi
done

# Clean up a broken repo file from a previous run (e.g. one pointing to kali-rolling)
$SUDO rm -f /etc/apt/sources.list.d/docker.list

# ---------- prerequisites ----------
c_info "Installing prerequisites..."
$SUDO apt-get update
$SUDO apt-get install -y ca-certificates curl

# ---------- GPG key + repo ----------
c_info "Adding Docker GPG key and repository..."
$SUDO install -m 0755 -d /etc/apt/keyrings
$SUDO curl -fsSL "https://download.docker.com/linux/${DOCKER_DISTRO}/gpg" -o /etc/apt/keyrings/docker.asc
$SUDO chmod a+r /etc/apt/keyrings/docker.asc

echo "deb [arch=${ARCH} signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/${DOCKER_DISTRO} ${CODENAME} stable" \
    | $SUDO tee /etc/apt/sources.list.d/docker.list >/dev/null

# ---------- install ----------
c_info "Installing Docker CE..."
$SUDO apt-get update
$SUDO apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# ---------- service ----------
if command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then
    $SUDO systemctl enable --now docker
else
    c_warn "systemd not detected - start Docker manually: sudo service docker start"
fi

# ---------- docker group ----------
getent group docker >/dev/null || $SUDO groupadd docker
if [ "$TARGET_USER" != "root" ]; then
    $SUDO usermod -aG docker "$TARGET_USER"
    c_ok "User '$TARGET_USER' added to the 'docker' group."
fi

# ---------- verify ----------
c_ok "Docker installed: $($SUDO docker --version)"
c_ok "Compose installed: $($SUDO docker compose version)"

if [ "${SKIP_TEST:-0}" != "1" ]; then
    c_info "Running hello-world test..."
    $SUDO docker run --rm hello-world
fi

echo
c_ok "Done."
if [ "$TARGET_USER" != "root" ]; then
    c_warn "Log out and back in (or run: newgrp docker) to use docker without sudo."
fi
