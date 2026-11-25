#!/usr/bin/env bash
# Inventory of the machine this runs on, as Markdown on stdout.
# Run it inside a remote agent sandbox to see what the provider preinstalls:
#   bash scripts/probe.sh > research/probes/<provider>/<YYYY-MM-DD>.md
# Read-only. Prints environment variable NAMES only, never values.
set -u
export LC_ALL=C
TO=8   # seconds per command

have() { command -v "$1" >/dev/null 2>&1; }
run()  { timeout "$TO" "$@" 2>&1 | head -n "${LINES_MAX:-1}"; }
ver()  { # ver <label> <cmd> [args...]: first line of the version output, or "-"
  local label=$1; shift
  if have "$1"; then printf '| %s | %s | `%s` |\n' "$label" "$(run "$@" | tr '|' '/' | tr -d '\r')" "$(command -v "$1")"
  else printf '| %s | - | |\n' "$label"; fi
}
h() { printf '\n## %s\n\n' "$1"; }

echo "# Probe: $(hostname 2>/dev/null) $(date -u +%Y-%m-%dT%H:%M:%SZ)"

h "System"
echo '```'
grep -E '^(PRETTY_NAME|VERSION_ID|ID)=' /etc/os-release 2>/dev/null
echo "kernel: $(uname -srm)"
echo "virt:   $(have systemd-detect-virt && systemd-detect-virt 2>/dev/null; have systemd-detect-virt && systemd-detect-virt -c 2>/dev/null)"
echo "init:   $(ps -p 1 -o comm= 2>/dev/null)"
echo "cpus:   $(nproc 2>/dev/null)  model: $(grep -m1 'model name' /proc/cpuinfo 2>/dev/null | cut -d: -f2 | xargs)"
free -h 2>/dev/null | head -2
df -h / /tmp "$HOME" 2>/dev/null | awk 'NR==1 || !seen[$0]++'
for f in /sys/fs/cgroup/cpu.max /sys/fs/cgroup/memory.max; do [ -r "$f" ] && echo "$f: $(cat "$f")"; done
echo "user:   $(id)"
echo "sudo:   $(sudo -n true 2>/dev/null && echo passwordless || echo no)"
echo "shell:  ${SHELL:-?}  home: $HOME  cwd: $PWD"
echo '```'

h "Languages and runtimes"
echo '| Tool | Version | Path |'; echo '| --- | --- | --- |'
ver python3 python3 --version; ver python python --version; ver pip pip --version
ver uv uv --version; ver poetry poetry --version; ver pipx pipx --version
ver node node --version; ver npm npm --version; ver pnpm pnpm --version; ver yarn yarn --version
ver bun bun --version; ver deno deno --version
ver go go version; ver rustc rustc --version; ver cargo cargo --version
ver java java -version; ver mvn mvn -v; ver gradle gradle --version
ver ruby ruby --version; ver php php --version; ver composer composer --version
ver dotnet dotnet --version; ver swift swift --version; ver elixir elixir --version
ver gcc gcc --version; ver clang clang --version; ver cmake cmake --version; ver make make --version
ver nix nix --version

h "Version managers"
echo '```'
have pyenv  && { echo "pyenv:";  run pyenv versions --bare | head -20; }
[ -d "${NVM_DIR:-$HOME/.nvm}/versions/node" ] && { echo "nvm:"; ls "${NVM_DIR:-$HOME/.nvm}/versions/node"; }
have mise   && { echo "mise:";   LINES_MAX=40 run mise ls; }
have asdf   && { echo "asdf:";   LINES_MAX=40 run asdf list; }
have rustup && { echo "rustup:"; LINES_MAX=20 run rustup toolchain list; }
ls -d /opt/* 2>/dev/null | head -40
echo '```'

h "Containers, browsers, databases"
echo '| Tool | Version | Path |'; echo '| --- | --- | --- |'
ver docker docker --version; ver "docker compose" docker compose version; ver podman podman --version
echo "| docker daemon reachable | $(timeout "$TO" docker info >/dev/null 2>&1 && echo yes || echo no) | |"
ver google-chrome google-chrome --version; ver chromium chromium --version; ver chromium-browser chromium-browser --version
ver firefox firefox --version; ver chromedriver chromedriver --version
echo "| playwright browsers | $(ls "$HOME/.cache/ms-playwright" 2>/dev/null | tr '\n' ' ' || true) | |"
ver psql psql --version; ver postgres postgres --version; ver redis-server redis-server --version
ver mysql mysql --version; ver mongod mongod --version; ver sqlite3 sqlite3 --version

h "CLI tools"
echo '| Tool | Version | Path |'; echo '| --- | --- | --- |'
for t in git git-lfs gh glab rg fd fdfind jq yq fzf tmux screen vim nvim nano curl wget rsync zip unzip \
         ffmpeg convert magick make bazel kubectl terraform aws gcloud az; do ver "$t" "$t" --version; done
ver ssh ssh -V

h "Coding agents present"
echo '| Tool | Version | Path |'; echo '| --- | --- | --- |'
for t in claude codex amp opencode cursor-agent gemini copilot devin jules pi aider; do ver "$t" "$t" --version; done

h "Package counts"
echo '```'
have dpkg && echo "dpkg packages: $(dpkg -l 2>/dev/null | grep -c '^ii')"
have rpm  && echo "rpm packages:  $(rpm -qa 2>/dev/null | wc -l)"
have pip3 && echo "pip packages (python3): $(timeout "$TO" pip3 list 2>/dev/null | tail -n +3 | wc -l)"
have npm  && { echo "npm globals:"; timeout "$TO" npm ls -g --depth=0 2>/dev/null | tail -n +2; }
echo '```'

h "Network"
echo '```'
env | cut -d= -f1 | grep -iE 'proxy' | sort | sed 's/^/proxy var set: /'
for u in https://pypi.org https://registry.npmjs.org https://github.com https://api.github.com \
         https://crates.io https://proxy.golang.org https://deb.debian.org https://example.com https://www.google.com; do
  code=$(curl -s -o /dev/null -m 6 -A sandbox-probe -w '%{http_code}' "$u" 2>/dev/null); echo "$u -> ${code:-000}"
done
grep -E '^nameserver' /etc/resolv.conf 2>/dev/null
echo '```'

h "Environment variable names (values not shown)"
echo '```'
env | cut -d= -f1 | grep -vE '^(_|SHLVL|PWD|OLDPWD)$' | sort | tr '\n' ' '; echo
echo '```'
