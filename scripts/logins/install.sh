#!/bin/bash
# Install the login tools on the sandbox host. Run as root from a checkout of this repository.
#   install.sh [path/to/infisical.env]
# Installs:
#   /usr/local/bin/sandbox-secrets      Infisical client (get / set / list / delete)
#   /usr/local/bin/codex-plan-proxy     login, status (run with sudo)
#   codex-plan-proxy.service            the proxy, as the unprivileged user `llmproxy`
# The Infisical settings of the host's machine identity go to /etc/sandbox-logins/infisical.env
# (root:incus-admin, 0640): members of incus-admin already control every sandbox.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
LISTEN=${CODEX_PROXY_LISTEN:-$(incus network get "${NET:-incusbr0}" ipv4.address | cut -d/ -f1):8455}
ALLOW=${CODEX_PROXY_ALLOW:-$(python3 -c 'import ipaddress,sys; print(ipaddress.ip_interface(sys.argv[1]).network)' "$(incus network get "${NET:-incusbr0}" ipv4.address)")}

id llmproxy >/dev/null 2>&1 || useradd --system --no-create-home --shell /usr/sbin/nologin llmproxy

install -d -m 755 /usr/local/lib/sandbox-logins
install -m 644 "$here/infisical.py" "$here/codex_plan_proxy.py" /usr/local/lib/sandbox-logins/
printf '#!/bin/sh\nexec /usr/bin/python3 /usr/local/lib/sandbox-logins/infisical.py "$@"\n' > /usr/local/bin/sandbox-secrets
printf '#!/bin/sh\nexec /usr/bin/python3 /usr/local/lib/sandbox-logins/codex_plan_proxy.py "$@"\n' > /usr/local/bin/codex-plan-proxy
chmod 755 /usr/local/bin/sandbox-secrets /usr/local/bin/codex-plan-proxy

install -d -m 750 -o root -g incus-admin /etc/sandbox-logins
if [ -n "${1:-}" ]; then
  install -m 640 -o root -g incus-admin "$1" /etc/sandbox-logins/infisical.env
fi
[ -f /etc/sandbox-logins/infisical.env ] || echo "note: no /etc/sandbox-logins/infisical.env yet; backups and secret injection are off"

install -d -m 700 -o llmproxy -g llmproxy /var/lib/codex-plan-proxy

cat > /etc/systemd/system/codex-plan-proxy.service <<EOF
[Unit]
Description=ChatGPT plan login proxy for agent sandboxes
Documentation=https://developers.openai.com/siwc/token-sharing-open-source
After=network-online.target incus.service
Wants=network-online.target

[Service]
User=llmproxy
Group=llmproxy
EnvironmentFile=-/etc/sandbox-logins/infisical.env
Environment=CODEX_PROXY_LISTEN=$LISTEN
Environment=CODEX_PROXY_ALLOW=$ALLOW
ExecStart=/usr/bin/python3 /usr/local/lib/sandbox-logins/codex_plan_proxy.py serve
Restart=always
RestartSec=5
StateDirectory=codex-plan-proxy
StateDirectoryMode=0700
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=yes
PrivateTmp=yes
PrivateDevices=yes
ProtectKernelTunables=yes
ProtectKernelModules=yes
ProtectControlGroups=yes
RestrictAddressFamilies=AF_INET AF_INET6
RestrictNamespaces=yes
LockPersonality=yes
MemoryDenyWriteExecute=yes
CapabilityBoundingSet=
SystemCallArchitectures=native

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable codex-plan-proxy.service >/dev/null 2>&1
systemctl restart codex-plan-proxy.service
sleep 1
systemctl --no-pager --lines=3 status codex-plan-proxy.service | sed -n '1,4p;$p'
echo "proxy on $LISTEN for $ALLOW; sign in with: sudo codex-plan-proxy login"
