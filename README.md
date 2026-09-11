# WireGuard quick-start guide

Set up an Ubuntu server as an internet VPN gateway for Linux clients. Commands below use the interface name `wg0` and subnet `10.0.0.0/24`. Choose a different subnet throughout if it overlaps your server network or a client's local network.

## Before you begin

- Use an Ubuntu release receiving security updates, with root/sudo access and systemd.
- Secure SSH and keep a provider console available while changing networking.
- Allow inbound **UDP 51820** in both your provider's firewall/security group and your host firewall. If UFW is already active, use `sudo ufw allow 51820/udp`. Preserve SSH access; do not blindly enable or reset a firewall.
- The examples use iptables forwarding and NAT rules. If another firewall manager controls forwarding, reconcile these rules with its policy. The rules permit VPN clients to reach networks accessible through the server's outbound interface.
- The installer automatically checks direct IPv6 HTTPS connectivity and configures server IPv6 when it succeeds. An IPv6 route alone does not prove connectivity.

## Server setup

### Automated setup

Download and inspect the script before running it on your server:

```bash
wget https://raw.githubusercontent.com/daniel-z-johnson/wireguard-quick-startup-guide/main/setup-wireguard.sh
less setup-wireguard.sh
chmod +x setup-wireguard.sh
sudo ./setup-wireguard.sh
```

Optional flags (combine as needed):

```bash
sudo ./setup-wireguard.sh --ipv6 --interface ens5 --upgrade
```

- No IPv6 flag: automatically configure server IPv6 if the check passes; otherwise continue with an IPv4-only server.
- `--ipv6`: require a successful IPv6 check; stop before creating keys/configuration if it fails. Package installation may already have completed.
- `--no-ipv6`: skip detection and server IPv6 configuration.
- `--interface NAME`: override IPv4 outbound-interface detection. Without it, the script uses the route to `1.1.1.1`; it stops if detection fails.
- `--upgrade`: upgrade all installed packages. By default, the script refreshes package metadata and installs WireGuard, iptables, curl, and CA certificates.

The check tries direct HTTPS over IPv6 to Cloudflare (`2606:4700:4700::1111`) and Google (`2001:4860:4860::8888`), stopping after the first success. Each attempt has a 5-second connection timeout and a 10-second overall timeout. It bypasses proxies, verifies TLS, and detects the IPv6 outbound interface separately. A failed check can mean missing connectivity, blocked HTTPS, or an unavailable probe. Success verifies server outbound HTTPS, not end-to-end client forwarding; test that after setup.

The script creates keys and `/etc/wireguard/wg0.conf`, writes `/etc/sysctl.d/99-wireguard-forwarding.conf`, applies forwarding settings, and enables/starts `wg-quick@wg0`. It does not configure inbound host/cloud firewall rules.

**Existing setups are protected:** the script refuses to run if its keys, configuration, forwarding file, or interface already exist. It does not rotate keys or erase peers. If setup fails partway through, inspect the error and existing files before completing setup manually; do not delete keys just to rerun it. A failed interface startup can also leave partially applied firewall rules that need inspection.

Save the displayed server public key, then continue to [Client setup](#client-setup). Schedule a reboot if requested.

### Manual setup (IPv4)

1. Install the packages:

   ```bash
   sudo apt-get update
   sudo apt-get install -y wireguard iptables
   ```

2. Enable forwarding using a dedicated file. Inspect any existing file before replacing it:

   ```bash
   echo 'net.ipv4.ip_forward=1' | sudo tee /etc/sysctl.d/99-wireguard-forwarding.conf
   sudo sysctl -p /etc/sysctl.d/99-wireguard-forwarding.conf
   ```

3. Generate keys with restrictive permissions. These commands refuse to overwrite existing key files:

   ```bash
   sudo install -d -m 700 /etc/wireguard
   sudo bash -c 'set -euo pipefail; umask 077; set -C; wg genkey > /etc/wireguard/privatekey; wg pubkey < /etc/wireguard/privatekey > /etc/wireguard/publickey'
   sudo cat /etc/wireguard/publickey
   ```

4. Find the outbound interface:

   ```bash
   ip -4 route get 1.1.1.1
   ```

   Use the name after `dev` (for example, `ens5`) in place of `WAN_INTERFACE` below. Read the private key privately with `sudo cat /etc/wireguard/privatekey`; never share it.

5. Create a protected configuration file, then edit it. The creation command refuses to overwrite an existing configuration:

   ```bash
   sudo bash -c 'umask 077; set -C; : > /etc/wireguard/wg0.conf'
   sudoedit /etc/wireguard/wg0.conf
   ```

   Replace both placeholders in this configuration:

   ```ini
   [Interface]
   Address = 10.0.0.1/24
   ListenPort = 51820
   PrivateKey = SERVER_PRIVATE_KEY
   PostUp = iptables -I FORWARD 1 -i %i -o WAN_INTERFACE -s 10.0.0.0/24 -j ACCEPT
   PostUp = iptables -I FORWARD 1 -i WAN_INTERFACE -o %i -d 10.0.0.0/24 -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
   PostUp = iptables -t nat -A POSTROUTING -s 10.0.0.0/24 -o WAN_INTERFACE -j MASQUERADE
   PostDown = iptables -D FORWARD -i %i -o WAN_INTERFACE -s 10.0.0.0/24 -j ACCEPT
   PostDown = iptables -D FORWARD -i WAN_INTERFACE -o %i -d 10.0.0.0/24 -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
   PostDown = iptables -t nat -D POSTROUTING -s 10.0.0.0/24 -o WAN_INTERFACE -j MASQUERADE
   ```

For manual dual-stack setup, also add `fd86:ea04:1111::1/64` to the server address and the IPv6 `PostUp`/`PostDown` rules shown in [setup-wireguard.sh](setup-wireguard.sh), substituting your actual IPv6 outbound interface. Add `net.ipv6.conf.INTERFACE.accept_ra=2` and `net.ipv6.conf.all.forwarding=1` to the dedicated sysctl file (replace `INTERFACE`), then apply it again. The `accept_ra` setting preserves router-advertisement learning when forwarding is enabled. Verify IPv6 connectivity afterward.

Continue below to add a client before starting the service.

## Client setup

These instructions use a Linux client with `wg-quick`.

1. Install WireGuard:

   ```bash
   sudo apt-get update
   sudo apt-get install -y wireguard
   ```

2. Check DNS integration with `command -v resolvconf`. The `DNS` setting below requires a working compatible `resolvconf` command. If absent, configure your distribution's resolver integration before bringing up the tunnel; installation of WireGuard alone does not guarantee it. See the [wg-quick manual](https://git.zx2c4.com/wireguard-tools/about/src/man/wg-quick.8).

3. Generate client keys. The subshell protects new files and refuses to overwrite existing ones:

   ```bash
   (set -euo pipefail; umask 077; set -C; wg genkey > ~/client_privatekey; wg pubkey < ~/client_privatekey > ~/client_publickey)
   cat ~/client_publickey
   ```

4. Create and edit a protected configuration:

   ```bash
   sudo install -d -m 700 /etc/wireguard
   sudo bash -c 'umask 077; set -C; : > /etc/wireguard/wg0.conf'
   sudoedit /etc/wireguard/wg0.conf
   ```

   Replace the placeholders. Obtain the client private key from `~/client_privatekey` and the server public key from the server:

   ```ini
   [Interface]
   PrivateKey = CLIENT_PRIVATE_KEY
   Address = 10.0.0.2/32
   DNS = 1.1.1.1

   [Peer]
   PublicKey = SERVER_PUBLIC_KEY
   Endpoint = SERVER_PUBLIC_IP_OR_DOMAIN:51820
   AllowedIPs = 0.0.0.0/0, ::/0
   PersistentKeepalive = 25
   ```

   **Keep both default routes even when the server is IPv4-only.** `::/0` sends IPv6 traffic into the active tunnel so it does not bypass the VPN through the client's native IPv6 connection. Without server IPv6 support, that traffic fails; applications may fall back to IPv4. This configuration is not a kill switch: traffic can use the ordinary connection when the VPN is down.

   For a server configured with IPv6, use these client values instead:

   ```ini
   Address = 10.0.0.2/32, fd86:ea04:1111::2/128
   DNS = 1.1.1.1, 2606:4700:4700::1111
   ```

   Keep the peer's `AllowedIPs = 0.0.0.0/0, ::/0` in both modes. Enclose a literal IPv6 endpoint in brackets: `[SERVER_IPV6]:51820`.

   If you choose another configuration filename, replace `wg0` in all subsequent commands with that name, without `.conf`.

### Configure the server to accept the client

On the **server**, edit `/etc/wireguard/wg0.conf` and append only this section:

```ini
[Peer]
PublicKey = CLIENT_PUBLIC_KEY
AllowedIPs = 10.0.0.2/32
```

For dual-stack service, use `AllowedIPs = 10.0.0.2/32, fd86:ea04:1111::2/128`.

Each additional client needs its own key pair, address, and server peer section. For example, allocate `10.0.0.3/32` to the next client, plus `fd86:ea04:1111::3/128` if using IPv6.

Enable the server service and apply the configuration:

```bash
sudo systemctl enable wg-quick@wg0
sudo systemctl restart wg-quick@wg0
sudo systemctl status wg-quick@wg0 --no-pager
```

`restart` applies new peers even if automated setup already started the service; it briefly interrupts existing clients. Repeat it after subsequent configuration edits.

### Test the connection

On the **client**, record your public IPv4 address, then connect:

```bash
curl -4 https://ifconfig.co
sudo wg-quick up wg0
ping -c 3 10.0.0.1
sudo wg show
curl -4 https://ifconfig.co
```

After generating traffic, look for a recent handshake and increasing transfer counters. The public IPv4 address should match the server's internet-facing IPv4 address. For dual-stack service, also run `curl -6 https://ifconfig.co` and compare it with the same command on the server. Test ordinary domain names to verify DNS resolution.

To disconnect:

```bash
sudo wg-quick down wg0
```

To start automatically on future client boots:

```bash
sudo systemctl enable wg-quick@wg0
```

## Troubleshooting

- **Service fails:** inspect `sudo journalctl -u wg-quick@wg0 -b --no-pager`. For a manually started client, inspect the error from `sudo wg-quick up wg0`.
- **No handshake:** verify public keys, server peer entries, endpoint, UDP 51820 access, and that peer changes were applied. Check `sudo wg show` on both machines after generating traffic.
- **Handshake works but internet does not:** check `sysctl net.ipv4.ip_forward`, outbound interface names, `sudo iptables -S FORWARD`, and `sudo iptables -t nat -S POSTROUTING`. Existing firewall policies may override or remove rules.
- **DNS failure or `resolvconf: command not found`:** complete the client's resolver integration; see the DNS prerequisite above.
- **IPv6 fails:** verify server IPv6 internet access and forwarding, the separately detected IPv6 interface, IPv6 firewall/NAT rules, and the client/server IPv6 peer addresses.
- **Some networks fail:** check for overlap with `10.0.0.0/24`; choose a non-overlapping VPN subnet and update addresses, peer routes, and firewall rules consistently.

Key-generation guidance: [WireGuard Quick Start](https://www.wireguard.com/quickstart/).
