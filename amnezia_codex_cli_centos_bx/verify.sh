#!/usr/bin/env bash
set -u

NS="codexvpn"
IFACE="awg-codex"
FAILED=0

pass() { printf '[OK] %s\n' "$*"; }
fail() { printf '[FAIL] %s\n' "$*" >&2; FAILED=1; }

[[ ${EUID} -eq 0 ]] || {
    echo "Run this check as root." >&2
    exit 1
}

if systemctl is-active --quiet codex-vpn.service; then
    pass "codex-vpn.service is active"
else
    fail "codex-vpn.service is not active"
fi

if ip netns list | awk '{print $1}' | grep -Fxq "$NS"; then
    pass "network namespace $NS exists"
else
    fail "network namespace $NS is missing"
    exit "$FAILED"
fi

EXTRA_LINKS=$(ip -n "$NS" -brief link | awk '$1 != "lo" && $1 != "awg-codex" {print $1}')
if [[ -z "$EXTRA_LINKS" ]]; then
    pass "namespace contains no ordinary-network interface"
else
    fail "unexpected namespace interfaces: $EXTRA_LINKS"
fi

DEFAULT4=$(ip -n "$NS" route show default)
if printf '%s\n' "$DEFAULT4" | grep -Eq "^default dev ${IFACE}([[:space:]]|$)"; then
    pass "IPv4 default route uses $IFACE"
else
    fail "unexpected IPv4 default route: ${DEFAULT4:-none}"
fi

DEFAULT6=$(ip -n "$NS" -6 route show default)
if [[ -z "$DEFAULT6" ]]; then
    pass "no IPv6 default route (no IPv6 leak)"
else
    fail "unexpected IPv6 default route: $DEFAULT6"
fi

if ip netns exec "$NS" awg show "$IFACE" >/dev/null 2>&1; then
    pass "AmneziaWG interface is configured"
else
    fail "AmneziaWG interface is unavailable"
fi

HOST_IP=$(curl -4 -fsS --max-time 15 https://api.ipify.org 2>/dev/null || true)
VPN_IP=$(ip netns exec "$NS" curl -4 -fsS --max-time 15 https://api.ipify.org 2>/dev/null || true)

if [[ -n "$HOST_IP" ]]; then
    pass "host exit IP: $HOST_IP"
else
    fail "cannot determine host exit IP"
fi
if [[ -n "$VPN_IP" ]]; then
    pass "Codex exit IP: $VPN_IP"
else
    fail "cannot determine Codex exit IP"
fi

if [[ -n "$HOST_IP" && -n "$VPN_IP" && "$HOST_IP" != "$VPN_IP" ]]; then
    pass "host and Codex use different exits"
else
    fail "host and Codex exit IPs are not different"
fi

API_STATUS=$(ip netns exec "$NS" curl -4 -sS --max-time 20 -o /dev/null \
    -w '%{http_code}' https://api.openai.com/v1/models 2>/dev/null || true)
if [[ "$API_STATUS" == "401" ]]; then
    pass "OpenAI API is reachable (expected unauthenticated HTTP 401)"
else
    fail "unexpected OpenAI API response: ${API_STATUS:-connection failed}"
fi

TRACE=$(ip netns exec "$NS" curl -4 -fsS --max-time 15 \
    https://auth.openai.com/cdn-cgi/trace 2>/dev/null || true)
TRACE_LOC=$(printf '%s\n' "$TRACE" | sed -n 's/^loc=//p')
TRACE_COLO=$(printf '%s\n' "$TRACE" | sed -n 's/^colo=//p')
if [[ -n "$TRACE_LOC" ]]; then
    pass "Cloudflare location: $TRACE_LOC/$TRACE_COLO"
else
    fail "Cloudflare trace is unavailable"
fi

CODEX_PATH=$(command -v codex 2>/dev/null || true)
if [[ "$CODEX_PATH" == "/usr/local/bin/codex" ]]; then
    pass "the protected Codex wrapper is first in PATH"
else
    fail "unexpected Codex command: ${CODEX_PATH:-not found}"
fi

echo
ip netns exec "$NS" awg show "$IFACE"
exit "$FAILED"
