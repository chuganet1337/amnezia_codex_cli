#!/usr/bin/env bash
set -Eeuo pipefail

# Performs a recoverable clean reinstall of the Ubuntu stack.
# Usage: sudo ./reinstall.sh /path/to/amnezia.conf

die() {
    echo "ERROR: $*" >&2
    exit 1
}

[[ ${EUID} -eq 0 ]] || die "run this script as root"
[[ $# -eq 1 ]] || die "usage: sudo $0 /path/to/amnezia.conf"

SOURCE_CONFIG=$1
[[ -f "$SOURCE_CONFIG" ]] || die "configuration file not found: $SOURCE_CONFIG"

case "$SOURCE_CONFIG" in
    /root/.codex/*|/opt/openai-codex/*)
        die "move the AWG profile outside /root/.codex and /opt/openai-codex first"
        ;;
esac

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
[[ -x "$SCRIPT_DIR/install.sh" ]] || die "install.sh is missing or not executable"
[[ -x "$SCRIPT_DIR/uninstall.sh" ]] || die "uninstall.sh is missing or not executable"
[[ -x "$SCRIPT_DIR/verify.sh" ]] || die "verify.sh is missing or not executable"

if ip netns list | awk '{print $1}' | grep -Fxq codexvpn; then
    ACTIVE_PIDS=$(ip netns pids codexvpn 2>/dev/null || true)
    [[ -z "$ACTIVE_PIDS" ]] || die "stop Codex processes first. Active PIDs: $ACTIVE_PIDS"
fi

BACKUP_DIR="/root/amnezia-codex-backup-$(date +%Y%m%d-%H%M%S)"
install -d -m 700 "$BACKUP_DIR"

"$SCRIPT_DIR/uninstall.sh" --purge-config

if [[ -e /root/.codex ]]; then
    mv -- /root/.codex "$BACKUP_DIR/codex-home"
fi
if [[ -e /opt/openai-codex ]]; then
    mv -- /opt/openai-codex "$BACKUP_DIR/openai-codex"
fi

for profile in /root/.bashrc /root/.bash_profile /root/.profile /root/.zshrc /root/.zprofile; do
    [[ -f "$profile" ]] || continue
    if grep -Fxq '# >>> Codex installer >>>' "$profile" && \
       grep -Fxq '# <<< Codex installer <<<' "$profile"; then
        sed -i '/^# >>> Codex installer >>>$/,/^# <<< Codex installer <<<$/{d;}' "$profile"
    fi
done

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

"$SCRIPT_DIR/install.sh" "$SOURCE_CONFIG"
hash -r
"$SCRIPT_DIR/verify.sh"

echo
echo "Clean reinstall completed. Previous Codex state: $BACKUP_DIR"
echo "Log in again with: codex login --device-auth"
