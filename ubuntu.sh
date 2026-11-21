#!/usr/bin/env bash
# Dev setup for Pop!_OS / Ubuntu 24.04: C/C++, Python, Node.js, Go, Rust, Docker.
# Idempotent: safe to re-run. Run as your normal user (not root); sudo is used where needed.
set -euo pipefail

if [[ $EUID -eq 0 ]]; then
  echo "Run as a normal user, not root." >&2
  exit 1
fi

GO_VERSION="${GO_VERSION:-}"          # e.g. 1.23.4; empty = latest stable
NVM_VERSION="${NVM_VERSION:-v0.40.3}"
BASHRC="$HOME/.bashrc"
MARK="# >>> dev-setup >>>"

log() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }

# ---------------------------------------------------------------- APT packages
log "Installing base packages"
sudo apt update
sudo apt install -y \
build-essential \
gcc \
g++ \
make \
cmake \
ninja-build \
gdb \
clang \
clang-format \
clang-tidy \
libssl-dev \
openssl \
ca-certificates \
pkg-config \
git \
curl \
wget \
unzip \
zip \
autoconf \
automake \
libtool \
software-properties-common \
gnupg \
lsb-release \
jq \
htop \
tree \
valgrind \
lldb \
ccache \
bear \
cppcheck \
clangd \
python3 \
python3-pip \
python3-venv \
python3-dev \
pipx \
libbz2-dev \
libffi-dev \
liblzma-dev \
libncurses-dev \
libreadline-dev \
libsqlite3-dev \
tk-dev \
xz-utils \
zlib1g-dev

# ------------------------------------------------------------------ Shell env
# Single managed block in ~/.bashrc; each section below appends its lines to it.
touch "$BASHRC"
if ! grep -qF "$MARK" "$BASHRC"; then
  printf '\n%s\n# <<< dev-setup <<<\n' "$MARK" >> "$BASHRC"
fi
add_rc() {
  local line="$1"
  grep -qxF "$line" "$BASHRC" || sed -i "/^# <<< dev-setup <<</i $line" "$BASHRC"
}

# --------------------------------------------------------------------- Docker
if ! command -v docker >/dev/null 2>&1; then
  log "Installing Docker Engine (official repo)"
  # Pop!_OS reports ID=pop; use the Ubuntu base codename (noble).
  UBUNTU_CODENAME="$(. /etc/os-release && echo "${UBUNTU_CODENAME:-noble}")"
  sudo install -m 0755 -d /etc/apt/keyrings
  sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  sudo chmod a+r /etc/apt/keyrings/docker.asc
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $UBUNTU_CODENAME stable" \
    | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
  sudo apt update
  sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
else
  log "Docker already installed"
fi
sudo systemctl enable --now docker
getent group docker >/dev/null || sudo groupadd docker
sudo usermod -aG docker "$USER"   # takes effect after re-login

# --------------------------------------------------------------------- Python
log "Setting up Python tooling (pyenv, pipx, uv)"
if [[ ! -d "$HOME/.pyenv" ]]; then
  curl -fsSL https://pyenv.run | bash
fi
add_rc 'export PYENV_ROOT="$HOME/.pyenv"'
add_rc '[[ -d $PYENV_ROOT/bin ]] && export PATH="$PYENV_ROOT/bin:$PATH"'
add_rc 'command -v pyenv >/dev/null && eval "$(pyenv init - bash)"'
add_rc 'export PATH="$HOME/.local/bin:$PATH"'
export PATH="$HOME/.local/bin:$PATH"
pipx ensurepath >/dev/null || true
command -v uv >/dev/null 2>&1 || pipx install uv
command -v poetry >/dev/null 2>&1 || pipx install poetry
command -v ruff >/dev/null 2>&1 || pipx install ruff

# --------------------------------------------------------------------- Node.js
log "Installing Node.js (nvm + LTS)"
export NVM_DIR="$HOME/.nvm"
if [[ ! -s "$NVM_DIR/nvm.sh" ]]; then
  curl -fsSL "https://raw.githubusercontent.com/nvm-sh/nvm/$NVM_VERSION/install.sh" | PROFILE=/dev/null bash
fi
add_rc 'export NVM_DIR="$HOME/.nvm"'
add_rc '[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"'
add_rc '[ -s "$NVM_DIR/bash_completion" ] && . "$NVM_DIR/bash_completion"'
set +u
# shellcheck disable=SC1091
. "$NVM_DIR/nvm.sh"
nvm install --lts
nvm alias default 'lts/*'
set -u
corepack enable 2>/dev/null || npm install -g pnpm yarn

# ------------------------------------------------------------------------- Go
log "Installing Go"
if [[ -z "$GO_VERSION" ]]; then
  GO_VERSION="$(curl -fsSL 'https://go.dev/VERSION?m=text' | head -n1 | sed 's/^go//')"
fi
case "$(dpkg --print-architecture)" in
  amd64) GO_ARCH=amd64 ;;
  arm64) GO_ARCH=arm64 ;;
  *) echo "Unsupported arch for Go" >&2; exit 1 ;;
esac
if [[ "$(/usr/local/go/bin/go version 2>/dev/null | awk '{print $3}')" != "go$GO_VERSION" ]]; then
  tmp="$(mktemp -d)"
  curl -fsSL "https://go.dev/dl/go${GO_VERSION}.linux-${GO_ARCH}.tar.gz" -o "$tmp/go.tgz"
  sudo rm -rf /usr/local/go
  sudo tar -C /usr/local -xzf "$tmp/go.tgz"
  rm -rf "$tmp"
fi
add_rc 'export PATH="$PATH:/usr/local/go/bin:$HOME/go/bin"'
export PATH="$PATH:/usr/local/go/bin:$HOME/go/bin"
go install golang.org/x/tools/gopls@latest
go install github.com/go-delve/delve/cmd/dlv@latest

# ------------------------------------------------------------------------ Rust
log "Installing Rust (rustup)"
if ! command -v rustup >/dev/null 2>&1 && [[ ! -x "$HOME/.cargo/bin/rustup" ]]; then
  curl -fsSL https://sh.rustup.rs | sh -s -- -y --profile default
fi
add_rc '[ -f "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"'
# shellcheck disable=SC1091
. "$HOME/.cargo/env"
rustup component add rust-analyzer rustfmt clippy

# ------------------------------------------------------------------------ Git
log "Git defaults (only if unset)"
git config --global init.defaultBranch >/dev/null 2>&1 || git config --global init.defaultBranch main
git config --global pull.rebase >/dev/null 2>&1 || git config --global pull.rebase false

# ---------------------------------------------------------------------- Done
log "Done. Versions:"
gcc --version | head -n1
g++ --version | head -n1
cmake --version | head -n1
clang --version | head -n1
python3 --version
nvm --version | sed 's/^/nvm /'
node --version
go version
rustc --version
cargo --version
docker --version
cat <<'EOF'

Next steps:
  - Log out and back in (or run `newgrp docker`) so docker works without sudo.
  - Open a new terminal (or `source ~/.bashrc`) to load pyenv/nvm/go/cargo.
  - Install a Python via pyenv:  pyenv install 3.12 && pyenv global 3.12
  - Set git identity: git config --global user.name "..." && git config --global user.email "..."
EOF

