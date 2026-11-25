#!/bin/bash
# Checks a fresh copy of the ubuntu-agent template. Run as root inside the copy:
#   incus exec <copy> -- bash /root/verify.sh
# Prints PASS/FAIL per check and exits non-zero if anything failed.
set -u
fails=0
# runs on the first boot of a fresh copy: boot must settle quickly and SSH must listen
timeout 60 systemctl is-system-running --wait >/dev/null 2>&1 || true
check() { local name=$1; shift; if out=$("$@" 2>&1); then echo "PASS $name"; else echo "FAIL $name: $(echo "$out" | tail -2 | tr '\n' ' ')"; fails=$((fails+1)); fi; }
# non-interactive shell as agent, like an agent's `bash -c`, but with the PAM environment (sudo -i)
as_agent() { sudo -iu agent bash -c "$*"; }

for t in node npm pnpm bun python3 uv go rustc cargo gh git git-lfs docker jq yq rg fd fzf tmux dtach sqlite3 psql redis-server chromium claude codex opencode pi agent-browser; do
  flag=--version; case $t in tmux) flag=-V ;; go) flag=version ;; esac
  check "tool $t" as_agent "command -v $t >/dev/null && $t $flag >/dev/null 2>&1"
done
check "node default is first configured version" as_agent 'node --version | grep -q "^v24\."'
check "node 26 available" as_agent 'mise exec node@26 -- node --version | grep -q "^v26\."'
check "PATH without login shell (env -i + /etc/environment)" bash -c 'su agent -s /bin/bash -c "command -v claude && command -v node" >/dev/null'

check "dockerd not running before first use" bash -c '! systemctl is-active --quiet docker.service'
check "docker run hello-world (as agent)" as_agent 'docker run --rm hello-world | grep -q "Hello from Docker"'
check "docker storage is overlay" as_agent 'docker info 2>/dev/null | grep -qiE "storage driver: overlay"'

check "chromium screenshot without --no-sandbox" as_agent 'cd /tmp && chromium --headless --disable-gpu --screenshot=/tmp/shot.png about:blank >/dev/null 2>&1; test -s /tmp/shot.png'
check "postgres starts" bash -c 'systemctl start postgresql && sudo -u postgres psql -tAc "select 1" | grep -q 1 && systemctl stop postgresql'
check "redis starts" bash -c 'systemctl start redis-server && redis-cli ping | grep -q PONG && systemctl stop redis-server'

check "machine-id regenerated" bash -c 'test -s /etc/machine-id'
check "ssh host keys present" bash -c 'ls /etc/ssh/ssh_host_ed25519_key >/dev/null'
check "sshd config valid" bash -c 'install -d -m 755 /run/sshd && sshd -t'
check "first boot reached running" bash -c '[ "$(systemctl is-system-running)" = running ]'
check "ssh socket listening" systemctl is-active --quiet ssh.socket
check "no credentials in homes" bash -c '! ls /home/agent/.claude/.credentials.json /home/agent/.codex/auth.json /home/agent/.config/gh/hosts.yml /home/agent/.netrc /root/.netrc 2>/dev/null | grep -q .'
check "git identity unset" bash -c '! git config --system user.email && ! sudo -iu agent git config --global user.email'
check "timezone UTC" bash -c '[ "$(date +%Z)" = UTC ]'
check "no apt timers" bash -c '! systemctl is-enabled --quiet apt-daily.timer'

gw=$(ip route | awk '/^default/{print $3; exit}')
check "host SSH on the gateway blocked by the ACL ($gw:22)" bash -c "! timeout 4 bash -c '</dev/tcp/$gw/22' 2>/dev/null"
check "DNS via the gateway works" getent hosts pypi.org
check "internet reachable" bash -c 'curl -fsS -m 8 -o /dev/null https://pypi.org'

mem=$(awk '/^MemTotal|^MemAvailable/{v[$1]=$2} END{print int((v["MemTotal:"]-v["MemAvailable:"])/1024)}' /proc/meminfo)
echo "INFO idle memory used: ${mem} MB"
[ "$mem" -lt 250 ] && echo "PASS idle memory < 250 MB" || { echo "FAIL idle memory ${mem} MB"; fails=$((fails+1)); }

echo "== $fails failed"
exit "$fails"
