#!/bin/bash
# Build the ubuntu-agent template. Runs as root inside a fresh copy of images:ubuntu/24.04
# (see scripts/incus/build-agent-template.sh). Rebuild from base instead of re-running on an
# old template. No credentials go into the image; scripts/incus/new-sandbox.sh injects them.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
NODE_VERSIONS=${NODE_VERSIONS:-"24 26"}   # first one is the default
step() { printf '\n==> %s\n' "$*"; }
as_agent() { sudo -u agent -H env PATH="$AGENT_PATH" MISE_DATA_DIR=/opt/mise bash -lc "$*"; }

AGENT_PATH=/home/agent/.local/bin:/home/agent/.cargo/bin:/home/agent/.opencode/bin:/opt/mise/shims:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

step "Waiting for network"
for _ in $(seq 1 60); do getent hosts archive.ubuntu.com >/dev/null && break; sleep 1; done

step "No background apt (lock fights, CPU in every sandbox)"
systemctl disable --now apt-daily.timer apt-daily-upgrade.timer motd-news.timer 2>/dev/null || true
apt-get purge -y -qq unattended-upgrades >/dev/null 2>&1 || true

step "Base packages"
apt-get update -qq
apt-get install -y -qq --no-install-recommends \
  build-essential pkg-config cmake make patch \
  libssl-dev zlib1g-dev libffi-dev libsqlite3-dev libreadline-dev libbz2-dev liblzma-dev libxml2-dev libyaml-dev libpq-dev \
  git git-lfs curl wget ca-certificates gnupg openssh-client openssh-server sudo \
  unzip zip xz-utils zstd bzip2 file bc time \
  jq ripgrep fd-find fzf tree tmux dtach vim nano less man-db htop lsof procps psmisc strace \
  iproute2 iputils-ping dnsutils netcat-openbsd rsync sqlite3 shellcheck bubblewrap \
  locales tzdata ncurses-term \
  python3 python3-pip python3-venv python3-dev python-is-python3 \
  fonts-liberation fonts-noto-color-emoji >/dev/null
ln -sf /usr/bin/fdfind /usr/local/bin/fd
git lfs install --system >/dev/null

step "Locale en_US.UTF-8, timezone UTC"
sed -i 's/^# *en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
locale-gen >/dev/null
update-locale LANG=en_US.UTF-8
ln -sf /usr/share/zoneinfo/UTC /etc/localtime
echo UTC > /etc/timezone

step "User agent (uid 1000, passwordless sudo, locked password)"
if id ubuntu >/dev/null 2>&1; then
  usermod -l agent -d /home/agent -m -c Agent ubuntu
  groupmod -n agent ubuntu
fi
id agent >/dev/null 2>&1 || useradd -m -u 1000 -s /bin/bash -c Agent agent
passwd -l agent >/dev/null
echo 'agent ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/agent
chmod 440 /etc/sudoers.d/agent
install -d -o agent -g agent /home/agent/work /home/agent/.ssh -m 755
chmod 700 /home/agent/.ssh

step "Environment for login and non-login shells"
cat > /etc/environment <<EOF
PATH="$AGENT_PATH"
LANG="en_US.UTF-8"
TZ="UTC"
MISE_DATA_DIR="/opt/mise"
MISE_YES="1"
MISE_TRUSTED_CONFIG_PATHS="/home/agent/work"
PLAYWRIGHT_BROWSERS_PATH="/opt/ms-playwright"
DISABLE_AUTOUPDATER="1"
GIT_EDITOR="true"
PAGER="cat"
GIT_PAGER="cat"
GH_PAGER="cat"
GH_PROMPT_DISABLED="1"
GH_NO_UPDATE_NOTIFIER="1"
EDITOR="vim"
NPM_CONFIG_UPDATE_NOTIFIER="false"
NPM_CONFIG_FUND="false"
PIP_DISABLE_PIP_VERSION_CHECK="1"
DO_NOT_TRACK="1"
EOF
# pam_env covers SSH and sudo -i; profile.d covers shells that skip PAM (incus exec bash -l)
sed -e 's/^/export /' /etc/environment > /etc/profile.d/00-agent-env.sh

step "Hook for per-sandbox secrets (/etc/agent-secrets.env, written by sync-logins.sh)"
# The file does not exist in the image. KEY=value lines, root:agent 0640.
cat > /etc/profile.d/10-agent-secrets.sh <<'SECRETS'
if [ -r /etc/agent-secrets.env ]; then set -a; . /etc/agent-secrets.env; set +a; fi
SECRETS
for f in /etc/pam.d/sshd /etc/pam.d/sudo-i; do   # non-interactive `ssh host cmd` and `sudo -i` skip profile.d
  [ -f "$f" ] || continue
  grep -q agent-secrets "$f" || echo 'session optional pam_env.so envfile=/etc/agent-secrets.env user_readenv=0' >> "$f"
done

step "Git defaults (identity is injected per sandbox, never baked in)"
git config --system init.defaultBranch main
git config --system pull.ff only
git config --system push.autoSetupRemote true
git config --system fetch.prune true
git config --system advice.detachedHead false

step "GitHub CLI (official apt repo)"
curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg -o /etc/apt/keyrings/githubcli-archive-keyring.gpg
echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" > /etc/apt/sources.list.d/github-cli.list

step "Docker CE (official repo), socket-activated"
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu noble stable" > /etc/apt/sources.list.d/docker.list

step "mise (official apt repo)"
curl -fsSL https://mise.jdx.dev/gpg-key.pub | gpg --dearmor --yes -o /etc/apt/keyrings/mise-archive-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/mise-archive-keyring.gpg arch=amd64] https://mise.jdx.dev/deb stable main" > /etc/apt/sources.list.d/mise.list

apt-get update -qq
apt-get install -y -qq gh docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin mise >/dev/null
usermod -aG docker agent
install -d /etc/docker
cat > /etc/docker/daemon.json <<'EOF'
{ "log-driver": "json-file", "log-opts": { "max-size": "10m", "max-file": "3" } }
EOF
systemctl disable --now docker.service containerd.service >/dev/null 2>&1
systemctl enable docker.socket >/dev/null 2>&1

step "PostgreSQL and Redis, installed but stopped"
apt-get install -y -qq postgresql redis-server >/dev/null
systemctl disable --now postgresql redis-server >/dev/null 2>&1

step "Runtimes with mise: Node ($NODE_VERSIONS), pnpm, bun, Go, yq"
install -d -o agent -g agent /opt/mise /etc/mise
node_list=$(printf '"%s", ' $NODE_VERSIONS); node_list=${node_list%, }
cat > /etc/mise/config.toml <<EOF
[tools]
node = [$node_list]
pnpm = "latest"
bun = "latest"
go = "latest"
yq = "latest"
"npm:@mariozechner/pi-coding-agent" = "latest"
"npm:agent-browser" = "latest"

[settings]
experimental = false
EOF
# node first: the npm: backend needs npm on PATH
as_agent 'mise install node && mise install && mise reshim'

step "uv (manages other Pythons)"
curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR=/usr/local/bin UV_NO_MODIFY_PATH=1 sh >/dev/null

step "Rust (rustup, minimal + clippy + rustfmt)"
as_agent 'curl --proto =https --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal --component clippy,rustfmt --no-modify-path >/dev/null'

step "Playwright Chromium and its system dependencies in /opt/ms-playwright"
install -d -o agent -g agent /opt/ms-playwright
PATH="$AGENT_PATH" MISE_DATA_DIR=/opt/mise PLAYWRIGHT_BROWSERS_PATH=/opt/ms-playwright \
  npx -y playwright@latest install --with-deps chromium >/dev/null
chown -R agent:agent /opt/ms-playwright
chrome=$(find /opt/ms-playwright -path '*chrome-linux*/chrome' -type f | head -1)
[ -x "$chrome" ] || { echo "Chromium not found" >&2; exit 1; }
ln -sf "$chrome" /usr/local/bin/chromium
install -d -o agent -g agent /home/agent/.agent-browser
printf '{ "executablePath": "%s" }\n' "$chrome" > /home/agent/.agent-browser/config.json
chown agent:agent /home/agent/.agent-browser/config.json

step "Coding agents (latest at build time, self-update off)"
as_agent 'curl -fsSL https://claude.ai/install.sh | bash >/dev/null'
# Codex: the full release package, not the single binary. Current models run in "code mode",
# which needs codex-code-mode-host next to codex; the package also carries codex-exec-server.
tmp=$(mktemp -d)
curl -fsSL -o "$tmp/codex.tgz" https://github.com/openai/codex/releases/latest/download/codex-package-x86_64-unknown-linux-musl.tar.gz
rm -rf /opt/codex && install -d /opt/codex
tar -xzf "$tmp/codex.tgz" -C /opt/codex
rm -rf "$tmp"
for b in codex codex-code-mode-host codex-exec-server; do ln -sf "/opt/codex/bin/$b" "/usr/local/bin/$b"; done
as_agent 'curl -fsSL https://opencode.ai/install | bash >/dev/null 2>&1'
install -d -o agent -g agent /home/agent/.config/opencode
echo '{ "$schema": "https://opencode.ai/config.json", "autoupdate": false }' > /home/agent/.config/opencode/opencode.json
chown -R agent:agent /home/agent/.config

step "SSH: key only, host keys generated per copy"
cat > /etc/ssh/sshd_config.d/10-agent.conf <<'EOF'
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin no
EOF
cat > /etc/systemd/system/ssh-hostkeys.service <<'EOF'
[Unit]
Description=Generate SSH host keys for this sandbox
# Before ssh.service only: ordering it before ssh.socket creates a loop with sockets.target on the
# first boot (socket -> keys -> basic.target -> sockets.target -> socket) and delays SSH.
Before=ssh.service
ConditionPathExistsGlob=!/etc/ssh/ssh_host_*_key

[Service]
Type=oneshot
ExecStart=/usr/bin/ssh-keygen -A

[Install]
WantedBy=multi-user.target
EOF
systemctl enable ssh-hostkeys.service ssh.socket >/dev/null 2>&1

step "Version manifest"
as_agent 'cd /tmp && cat <<EOF > /tmp/manifest
built: $(date -u +%Y-%m-%dT%H:%M:%SZ)
os: $(. /etc/os-release; echo $PRETTY_NAME)
node: $(mise ls --current node 2>/dev/null | awk "{print \$2}" | tr "\n" " ")
pnpm: $(pnpm --version)
bun: $(bun --version)
python: $(python3 --version | cut -d" " -f2)
uv: $(uv --version | cut -d" " -f2)
go: $(go version | cut -d" " -f3)
rust: $(rustc --version | cut -d" " -f2)
docker: $(docker --version | cut -d" " -f3 | tr -d ,)
gh: $(gh --version | head -1 | cut -d" " -f3)
chromium: $(chromium --version 2>/dev/null)
claude: $(claude --version 2>/dev/null)
codex: $(codex --version 2>/dev/null)
opencode: $(opencode --version 2>/dev/null)
pi: $(pi --version 2>&1 | tail -1)
agent-browser: $(agent-browser --version 2>/dev/null)
EOF'
install -m 644 /tmp/manifest /etc/agent-image-manifest
cat /etc/agent-image-manifest

step "Cleanup"
apt-get clean
rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* /root/.cache /root/.npm /home/agent/.cache /home/agent/.npm
rm -f /home/agent/.bash_history /root/.bash_history /etc/ssh/ssh_host_*
truncate -s 0 /etc/machine-id
rm -f /var/lib/dbus/machine-id
journalctl --vacuum-time=1s >/dev/null 2>&1 || true
fstrim / 2>/dev/null || true
echo "build done"
