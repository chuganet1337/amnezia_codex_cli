#!/usr/bin/env bash
set -Eeuo pipefail

NS="codexvpn"
SERVICE="codex-vpn.service"
PURGE_CONFIG=0

[[ ${EUID} -eq 0 ]] || {
    echo "ERROR: run this script as root" >&2
    exit 1
}

if [[ ${1:-} == "--purge-config" ]]; then
    PURGE_CONFIG=1
elif [[ $# -ne 0 ]]; then
    echo "Usage: sudo $0 [--purge-config]" >&2
    exit 2
fi

if ip netns list | awk '{print $1}' | grep -Fxq "$NS"; then
    ACTIVE_PIDS=$(ip netns pids "$NS" 2>/dev/null || true)
    if [[ -n "$ACTIVE_PIDS" ]]; then
        echo "ERROR: stop Codex processes first. Active PIDs: $ACTIVE_PIDS" >&2
        exit 1
    fi
fi

systemctl disable --now "$SERVICE" 2>/dev/null || true

if ip netns list | awk '{print $1}' | grep -Fxq "$NS"; then
    ip netns delete "$NS"
fi

rm -f -- "/etc/systemd/system/${SERVICE}"
rm -f -- /usr/local/sbin/codex-vpn-netns

if [[ -f /usr/local/bin/codex ]] && \
   grep -q 'Managed by amnezia-codex-cli' /usr/local/bin/codex; then
    rm -f -- /usr/local/bin/codex
fi

if [[ -f /etc/amnezia-codex/real-codex-path ]]; then
    REAL_CODEX=$(head -n1 /etc/amnezia-codex/real-codex-path)
    if [[ -x "$REAL_CODEX" && ! -e /usr/local/bin/codex && "$REAL_CODEX" == /usr/local/* ]]; then
        ln -s -- "$REAL_CODEX" /usr/local/bin/codex
        echo "Original Codex command restored at /usr/local/bin/codex"
    fi
fi

rm -f -- "/etc/netns/${NS}/resolv.conf"
rmdir "/etc/netns/${NS}" 2>/dev/null || true

if [[ $PURGE_CONFIG -eq 1 ]]; then
    rm -f -- /etc/amnezia-codex/awg0.conf
    rm -f -- /etc/amnezia-codex/real-codex-path
    rmdir /etc/amnezia-codex 2>/dev/null || true
    echo "VPN profile removed. Timestamped backups, if any, were preserved."
else
    echo "VPN profile preserved at /etc/amnezia-codex/awg0.conf"
fi

systemctl daemon-reload
echo "Codex VPN isolation removed. AmneziaWG packages were left installed."

echo "Reinstall Codex CLI if 'codex' is no longer found in PATH."
