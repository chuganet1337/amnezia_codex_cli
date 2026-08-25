#!/usr/bin/env bash
set -Eeuo pipefail

# Installs an isolated AmneziaWG network namespace for Codex CLI.
# Usage: sudo ./install.sh [--skip-packages] /path/to/amnezia.conf

NS="codexvpn"
IFACE="awg-codex"
SERVICE="codex-vpn.service"
CONFIG_DIR="/etc/amnezia-codex"
CONFIG_DST="${CONFIG_DIR}/awg0.conf"
NETNS_ETC="/etc/netns/${NS}"
REAL_CODEX=""
SKIP_PACKAGES=0
CODEX_INSTALLER_URL="https://chatgpt.com/codex/install.sh"
CODEX_INSTALL_DIR="/opt/openai-codex/bin"

die() {
    echo "ERROR: $*" >&2
    exit 1
}

usage() {
    echo "Usage: sudo $0 [--skip-packages] /path/to/amnezia.conf" >&2
    exit 2
}

remove_direct_codex_path_blocks() {
    local profile

    for profile in /root/.bashrc /root/.bash_profile /root/.profile /root/.zshrc /root/.zprofile; do
        [[ -f "$profile" ]] || continue
        if grep -Fxq '# >>> Codex installer >>>' "$profile" && \
           grep -Fxq '# <<< Codex installer <<<' "$profile"; then
            sed -i '/^# >>> Codex installer >>>$/,/^# <<< Codex installer <<<$/{d;}' "$profile"
            echo "Removed direct Codex PATH entry from $profile"
        fi
    done
}

[[ ${EUID} -eq 0 ]] || die "run this installer as root"

[[ -r /etc/os-release ]] || die "cannot identify the operating system"
# shellcheck disable=SC1091
source /etc/os-release
if [[ ${VERSION_ID%%.*} != "9" ]] || \
   [[ ${ID:-} != "centos" && ${ID_LIKE:-} != *rhel* && ${ID_LIKE:-} != *centos* ]]; then
    die "this installer supports CentOS Stream 9 and RHEL 9 compatible systems only"
fi

if [[ ${1:-} == "--skip-packages" ]]; then
    SKIP_PACKAGES=1
    shift
fi

[[ $# -eq 1 ]] || usage
SOURCE_CONFIG=$1
[[ -f "$SOURCE_CONFIG" ]] || die "configuration file not found: $SOURCE_CONFIG"

grep -qE '^[[:space:]]*\[Interface\][[:space:]]*$' "$SOURCE_CONFIG" || die "missing [Interface] section"
grep -qE '^[[:space:]]*PrivateKey[[:space:]]*=' "$SOURCE_CONFIG" || die "missing PrivateKey"
grep -qE '^[[:space:]]*Address[[:space:]]*=' "$SOURCE_CONFIG" || die "missing Address"
grep -qE '^[[:space:]]*\[Peer\][[:space:]]*$' "$SOURCE_CONFIG" || die "missing [Peer] section"
grep -qE '^[[:space:]]*Endpoint[[:space:]]*=' "$SOURCE_CONFIG" || die "missing Endpoint"
grep -qE '^[[:space:]]*AllowedIPs[[:space:]]*=.*0\.0\.0\.0/0' "$SOURCE_CONFIG" || \
    die "AllowedIPs must include 0.0.0.0/0 for a full Codex VPN route"
grep -qE '^[[:space:]]*Endpoint[[:space:]]*=[[:space:]]*[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+:[0-9]+[[:space:]]*$' \
    "$SOURCE_CONFIG" || die "Endpoint must use a numeric IPv4 address and port, not a hostname"

if [[ $SKIP_PACKAGES -eq 0 ]]; then
    dnf install -y dnf-plugins-core

    if ! rpm -q "kernel-devel-$(uname -r)" >/dev/null 2>&1; then
        dnf install -y "kernel-devel-$(uname -r)" || \
            die "matching kernel-devel is unavailable; do not upgrade/reboot automatically"
    fi

    dnf install -y kernel-headers dkms iproute curl ca-certificates bubblewrap
    dnf copr enable -y amneziavpn/amneziawg
    dnf install -y amneziawg-dkms amneziawg-tools
fi

command -v ip >/dev/null || die "iproute is not installed"
command -v awg >/dev/null || die "awg is not installed"
command -v awg-quick >/dev/null || die "awg-quick is not installed"
command -v curl >/dev/null || die "curl is not installed"
command -v bwrap >/dev/null || die "bubblewrap is not installed"

modprobe amneziawg

if ip link show awg-probe >/dev/null 2>&1; then
    die "temporary interface awg-probe already exists"
fi
ip link add awg-probe type amneziawg
ip link delete awg-probe

if ip netns list | awk '{print $1}' | grep -Fxq "$NS"; then
    ACTIVE_PIDS=$(ip netns pids "$NS" 2>/dev/null || true)
    [[ -z "$ACTIVE_PIDS" ]] || die "Codex processes are still running in $NS: $ACTIVE_PIDS"
fi

install -d -m 700 "$CONFIG_DIR"
install -d -m 755 "$NETNS_ETC"

if [[ -f "$CONFIG_DST" ]] && ! cmp -s "$SOURCE_CONFIG" "$CONFIG_DST"; then
    BACKUP="${CONFIG_DST}.backup.$(date +%Y%m%d-%H%M%S)"
    cp -p -- "$CONFIG_DST" "$BACKUP"
    chmod 600 "$BACKUP"
    echo "Previous VPN profile backed up to $BACKUP"
fi

TEMP_CONFIG=$(mktemp "${CONFIG_DIR}/awg0.conf.XXXXXX")
trap 'rm -f "$TEMP_CONFIG"' EXIT
install -m 600 "$SOURCE_CONFIG" "$TEMP_CONFIG"
sed -i 's/\r$//' "$TEMP_CONFIG"
sed -i -E '/^[[:space:]]*I[1-5][[:space:]]*=[[:space:]]*$/d' "$TEMP_CONFIG"
mv -f -- "$TEMP_CONFIG" "$CONFIG_DST"
chmod 600 "$CONFIG_DST"
trap - EXIT

interface_value() {
    local key=$1
    awk -F= -v wanted="$key" '
        /^[[:space:]]*\[Interface\][[:space:]]*$/ { inside=1; next }
        /^[[:space:]]*\[/ { inside=0 }
        inside && $1 ~ "^[[:space:]]*" wanted "[[:space:]]*$" {
            value=$0
            sub(/^[^=]*=/, "", value)
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
            print value
            exit
        }
    ' "$CONFIG_DST"
}

ADDRESS_LIST=$(interface_value Address)
ADDRESS4=$(printf '%s\n' "$ADDRESS_LIST" | tr ',' '\n' | \
    sed -E 's/^[[:space:]]+|[[:space:]]+$//g' | grep -m1 -E '^[0-9]+\.' || true)
[[ -n "$ADDRESS4" ]] || die "no IPv4 Address found in [Interface]"

DNS_LIST=$(interface_value DNS || true)
[[ -n "$DNS_LIST" ]] || DNS_LIST="1.1.1.1, 1.0.0.1"

MTU_VALUE=$(interface_value MTU || true)
[[ -n "$MTU_VALUE" ]] || MTU_VALUE=1420
[[ "$MTU_VALUE" =~ ^[0-9]+$ ]] || die "MTU must be numeric"

: > "${NETNS_ETC}/resolv.conf"
while IFS= read -r dns_server; do
    [[ "$dns_server" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] && \
        printf 'nameserver %s\n' "$dns_server" >> "${NETNS_ETC}/resolv.conf"
done < <(printf '%s\n' "$DNS_LIST" | tr ',' '\n' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')
if [[ ! -s "${NETNS_ETC}/resolv.conf" ]]; then
    printf 'nameserver 1.1.1.1\nnameserver 1.0.0.1\n' > "${NETNS_ETC}/resolv.conf"
fi
chmod 600 "${NETNS_ETC}/resolv.conf"

cat > /usr/local/sbin/codex-vpn-netns <<SCRIPT
#!/usr/bin/env bash
set -Eeuo pipefail

NS="$NS"
IFACE="$IFACE"
CONF="$CONFIG_DST"
ADDRESS4="$ADDRESS4"
MTU_VALUE="$MTU_VALUE"
RUNTIME_CONF=""

namespace_exists() {
    ip netns list | awk '{print \$1}' | grep -Fxq "\$NS"
}

cleanup_failed_start() {
    [[ -n "\$RUNTIME_CONF" ]] && rm -f -- "\$RUNTIME_CONF"
    if namespace_exists; then
        ip netns delete "\$NS" || true
    fi
}

start_vpn() {
    if namespace_exists; then
        ip netns exec "\$NS" awg show "\$IFACE" >/dev/null
        exit 0
    fi

    trap cleanup_failed_start ERR INT TERM
    ip netns add "\$NS"
    ip -n "\$NS" link set lo up

    # Creating the interface in the host namespace keeps the encrypted UDP
    # socket on the host's ordinary route after the interface is moved.
    ip link add "\$IFACE" type amneziawg
    ip link set "\$IFACE" netns "\$NS"

    umask 077
    RUNTIME_CONF=\$(mktemp /run/awg-codex.XXXXXX)
    awg-quick strip "\$CONF" > "\$RUNTIME_CONF"
    ip netns exec "\$NS" awg setconf "\$IFACE" "\$RUNTIME_CONF"
    rm -f -- "\$RUNTIME_CONF"
    RUNTIME_CONF=""

    ip -n "\$NS" address add "\$ADDRESS4" dev "\$IFACE"
    ip -n "\$NS" link set mtu "\$MTU_VALUE" dev "\$IFACE"
    ip -n "\$NS" link set "\$IFACE" up
    ip -n "\$NS" route add default dev "\$IFACE"
    trap - ERR INT TERM
}

stop_vpn() {
    if namespace_exists; then
        ip netns delete "\$NS"
    fi
}

case "\${1:-}" in
    start) start_vpn ;;
    stop)  stop_vpn ;;
    *) echo "Usage: \$0 {start|stop}" >&2; exit 2 ;;
esac
SCRIPT
chmod 700 /usr/local/sbin/codex-vpn-netns

cat > "/etc/systemd/system/${SERVICE}" <<UNIT
[Unit]
Description=Dedicated AmneziaWG network namespace for Codex
Wants=network-online.target
After=network-online.target
ConditionPathExists=$CONFIG_DST

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/sbin/codex-vpn-netns start
ExecStop=/usr/local/sbin/codex-vpn-netns stop
TimeoutStartSec=30
TimeoutStopSec=15

[Install]
WantedBy=multi-user.target
UNIT

systemctl stop "$SERVICE" 2>/dev/null || true
if ip netns list | awk '{print $1}' | grep -Fxq "$NS"; then
    ip netns delete "$NS"
fi
systemctl daemon-reload
systemctl enable --now "$SERVICE"

VPN_IP=$(ip netns exec "$NS" curl -4 -fsS --max-time 20 https://api.ipify.org || true)
[[ -n "$VPN_IP" ]] || die "AmneziaWG started, but the VPN public-IP test failed; Codex was not installed"
echo "AmneziaWG is active. VPN exit IP: $VPN_IP"

if [[ ! -x "$CODEX_INSTALL_DIR/codex" ]]; then
    echo "Installing the managed Codex CLI copy through the AmneziaWG namespace."
    install -d -m 755 "$CODEX_INSTALL_DIR"
    ip netns exec "$NS" env \
        -u HTTP_PROXY -u HTTPS_PROXY -u ALL_PROXY -u NO_PROXY \
        -u http_proxy -u https_proxy -u all_proxy -u no_proxy \
        HOME=/root \
        CODEX_HOME=/root/.codex \
        CODEX_INSTALL_DIR="$CODEX_INSTALL_DIR" \
        CODEX_NON_INTERACTIVE=1 \
        sh -c "curl -fsSL --max-time 60 '$CODEX_INSTALLER_URL' | sh"
fi
REAL_CODEX=$(readlink -f "$CODEX_INSTALL_DIR/codex" 2>/dev/null || true)
[[ -n "$REAL_CODEX" && -x "$REAL_CODEX" ]] || \
    die "Codex installation finished without an executable Codex binary"

# The official installer prepends CODEX_INSTALL_DIR to the shell PATH. Remove
# that block so interactive shells cannot bypass the fail-closed VPN wrapper.
remove_direct_codex_path_blocks

printf '%s\n' "$REAL_CODEX" > "${CONFIG_DIR}/real-codex-path"
chmod 600 "${CONFIG_DIR}/real-codex-path"

if [[ -e /usr/local/bin/codex ]] && ! grep -q 'Managed by amnezia-codex-cli' /usr/local/bin/codex 2>/dev/null; then
    WRAPPER_BACKUP="/usr/local/bin/codex.pre-amnezia.$(date +%Y%m%d-%H%M%S)"
    cp -p -- /usr/local/bin/codex "$WRAPPER_BACKUP"
    echo "Existing /usr/local/bin/codex backed up to $WRAPPER_BACKUP"
fi

cat > /usr/local/bin/codex <<'SCRIPT'
#!/usr/bin/env bash
# Managed by amnezia-codex-cli
set -Eeuo pipefail

SERVICE="codex-vpn.service"
NS="codexvpn"
REAL_CODEX="__REAL_CODEX__"

if ! systemctl is-active --quiet "$SERVICE"; then
    systemctl start "$SERVICE"
fi

if ! ip netns exec "$NS" awg show awg-codex >/dev/null 2>&1; then
    echo "Codex VPN namespace is unavailable; refusing to start." >&2
    exit 1
fi

exec ip netns exec "$NS" env \
    -u HTTP_PROXY -u HTTPS_PROXY -u ALL_PROXY -u NO_PROXY \
    -u http_proxy -u https_proxy -u all_proxy -u no_proxy \
    "$REAL_CODEX" "$@"
SCRIPT
sed -i "s|__REAL_CODEX__|$REAL_CODEX|" /usr/local/bin/codex
chmod 755 /usr/local/bin/codex

echo
echo "Installation complete. VPN exit IP: $VPN_IP"
echo "Codex CLI path: $REAL_CODEX"
echo "For this shell run: export PATH=\"/usr/local/bin:\$PATH\"; hash -r"
echo "For SSH/headless authentication run: codex login --device-auth"
