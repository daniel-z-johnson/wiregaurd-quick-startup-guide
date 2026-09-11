#!/bin/bash
# Initial WireGuard server setup for Ubuntu. Run with sudo.
set -euo pipefail
set -o noclobber
umask 077

UPGRADE=false
IPV6=false
IPV6_MODE=auto
WAN_INTERFACE=''
usage() {
    echo "Usage: sudo $0 [--upgrade] [--ipv6 | --no-ipv6] [--interface NAME]"
    echo "  --upgrade         Also upgrade all installed packages"
    echo "  Default: automatically check IPv6 internet access"
    echo "  --ipv6            Require IPv6 connectivity; stop if the check fails"
    echo "  --no-ipv6         Skip server IPv6 configuration"
    echo "  --interface NAME  Override automatic IPv4 outbound-interface detection"
}
while (($#)); do
    case "$1" in
        --upgrade) UPGRADE=true; shift ;;
        --ipv6) IPV6_MODE=required; shift ;;
        --no-ipv6) IPV6_MODE=disabled; shift ;;
        --interface)
            [[ $# -ge 2 && -n "$2" ]] || { usage >&2; exit 1; }
            WAN_INTERFACE=$2; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) usage >&2; exit 1 ;;
    esac
done
[[ $EUID -eq 0 ]] || { echo "Run this script with sudo." >&2; exit 1; }
# Refuse reruns before package, key, network, or configuration changes.
for existing in /etc/wireguard/wg0.conf /etc/wireguard/privatekey /etc/wireguard/publickey /etc/sysctl.d/99-wireguard-forwarding.conf; do
    if [[ -e "$existing" || -L "$existing" ]]; then
        echo "Refusing to overwrite $existing. Manage the existing setup manually." >&2
        exit 1
    fi
done
if ip link show wg0 >/dev/null 2>&1; then
    echo "wg0 already exists; manage the existing setup manually." >&2
    exit 1
fi
source /etc/os-release
[[ ${ID:-} == ubuntu ]] || { echo "This installer supports Ubuntu only." >&2; exit 1; }
trap 'echo "Setup failed at line $LINENO. Inspect the error and any files already created before retrying." >&2' ERR

# Resolve the actual route rather than assuming eth0 or selecting the first default.
if [[ -z "$WAN_INTERFACE" ]]; then
    WAN_INTERFACE=$(ip -4 route get 1.1.1.1 | awk '{for (i=1;i<=NF;i++) if ($i=="dev") {print $(i+1); exit}}')
fi
[[ "$WAN_INTERFACE" =~ ^[a-zA-Z0-9_.:-]+$ ]] || { echo "Cannot determine a valid outbound interface; use --interface NAME." >&2; exit 1; }
ip link show dev "$WAN_INTERFACE" >/dev/null
echo "Installing WireGuard and connectivity/firewall tools (outbound interface: $WAN_INTERFACE)..."
apt-get update
if $UPGRADE; then apt-get upgrade -y; fi
apt-get install -y wireguard iptables curl ca-certificates

# Verify direct IPv6 HTTPS access, bypassing proxies; a route alone is insufficient.
# Try independent destinations, with bounded timeouts and normal TLS verification.
IPV6_INTERFACE=''
if [[ "$IPV6_MODE" != disabled ]]; then
    echo "Checking IPv6 internet access (up to 10 seconds per destination)..."
    for probe in '2606:4700:4700::1111' '2001:4860:4860::8888'; do
        if candidate=$(ip -6 route get "$probe" 2>/dev/null | awk '{for (i=1;i<=NF;i++) if ($i=="dev") {print $(i+1); exit}}') &&
           [[ "$candidate" =~ ^[a-zA-Z0-9_.:-]+$ ]] &&
           curl --ipv6 --noproxy '*' --interface "$candidate" \
                --connect-timeout 5 --max-time 10 --fail --silent --output /dev/null \
                "https://[$probe]/"; then
            IPV6_INTERFACE=$candidate
            IPV6=true
            break
        fi
    done
    if $IPV6; then
        echo "IPv6 HTTPS check passed via $IPV6_INTERFACE; enabling server IPv6."
    elif [[ "$IPV6_MODE" == required ]]; then
        echo "IPv6 check failed; --ipv6 requires connectivity. No WireGuard keys/configuration were created." >&2
        exit 1
    else
        echo "IPv6 check failed; continuing with IPv4 server configuration only."
        echo "A blocked/unavailable probe can also cause this result; see README.md."
    fi
else
    echo "Server IPv6 configuration disabled by --no-ipv6."
fi

install -d -m 700 /etc/wireguard
wg genkey > /etc/wireguard/privatekey
wg pubkey < /etc/wireguard/privatekey > /etc/wireguard/publickey
PRIVATE_KEY=$(cat /etc/wireguard/privatekey)
ADDRESS='10.0.0.1/24'
if $IPV6; then ADDRESS+=', fd86:ea04:1111::1/64'; fi
cat > /etc/wireguard/wg0.conf <<EOF
[Interface]
Address = $ADDRESS
ListenPort = 51820
PrivateKey = $PRIVATE_KEY
PostUp = iptables -I FORWARD 1 -i %i -o $WAN_INTERFACE -s 10.0.0.0/24 -j ACCEPT
PostUp = iptables -I FORWARD 1 -i $WAN_INTERFACE -o %i -d 10.0.0.0/24 -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
PostUp = iptables -t nat -A POSTROUTING -s 10.0.0.0/24 -o $WAN_INTERFACE -j MASQUERADE
PostDown = iptables -D FORWARD -i %i -o $WAN_INTERFACE -s 10.0.0.0/24 -j ACCEPT || true
PostDown = iptables -D FORWARD -i $WAN_INTERFACE -o %i -d 10.0.0.0/24 -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT || true
PostDown = iptables -t nat -D POSTROUTING -s 10.0.0.0/24 -o $WAN_INTERFACE -j MASQUERADE || true
EOF
unset PRIVATE_KEY
if $IPV6; then
    cat >> /etc/wireguard/wg0.conf <<EOF
PostUp = ip6tables -I FORWARD 1 -i %i -o $IPV6_INTERFACE -s fd86:ea04:1111::/64 -j ACCEPT
PostUp = ip6tables -I FORWARD 1 -i $IPV6_INTERFACE -o %i -d fd86:ea04:1111::/64 -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
PostUp = ip6tables -t nat -A POSTROUTING -s fd86:ea04:1111::/64 -o $IPV6_INTERFACE -j MASQUERADE
PostDown = ip6tables -D FORWARD -i %i -o $IPV6_INTERFACE -s fd86:ea04:1111::/64 -j ACCEPT || true
PostDown = ip6tables -D FORWARD -i $IPV6_INTERFACE -o %i -d fd86:ea04:1111::/64 -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT || true
PostDown = ip6tables -t nat -D POSTROUTING -s fd86:ea04:1111::/64 -o $IPV6_INTERFACE -j MASQUERADE || true
EOF
fi
printf '\n# Append one [Peer] section per client; see README.md.\n' >> /etc/wireguard/wg0.conf
printf 'net.ipv4.ip_forward=1\n' > /etc/sysctl.d/99-wireguard-forwarding.conf
if $IPV6; then
    # Preserve router-advertisement learning when enabling router mode.
    printf 'net.ipv6.conf.%s.accept_ra=2\nnet.ipv6.conf.all.forwarding=1\n' "$IPV6_INTERFACE" >> /etc/sysctl.d/99-wireguard-forwarding.conf
fi
sysctl -p /etc/sysctl.d/99-wireguard-forwarding.conf
if ! systemctl enable --now wg-quick@wg0; then
    echo "WireGuard failed to start. Inspect: journalctl -u wg-quick@wg0 -b" >&2
    exit 1
fi
systemctl status wg-quick@wg0 --no-pager
echo "Server public key:"
cat /etc/wireguard/publickey
echo "Next: allow inbound UDP 51820 in host/cloud firewalls, then add client peers."
echo "After editing peers: sudo systemctl restart wg-quick@wg0"
echo "Verify handshakes with: sudo wg show"
echo "IPv6 enabled: $IPV6. Follow the matching client instructions in README.md."
echo "Keep client AllowedIPs = 0.0.0.0/0, ::/0 to route both families into the active VPN."
if [[ -f /var/run/reboot-required ]]; then
    echo "A reboot is required; schedule it after completing setup."
fi
