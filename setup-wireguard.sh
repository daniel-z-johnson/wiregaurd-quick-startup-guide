#!/bin/bash

# WireGuard Server Setup Script for Ubuntu
# This script automates the initial WireGuard VPN server setup
# 
# Requirements: Ubuntu 20.04 or later, root/sudo access
# Usage: sudo ./setup-wireguard.sh

set -e  # Exit on any error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if script is run as root
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Error: This script must be run as root or with sudo${NC}"
    exit 1
fi

echo -e "${GREEN}=== WireGuard Server Setup Script ===${NC}"
echo ""

# Step 1: Update and upgrade the system
echo -e "${YELLOW}Step 1: Updating and upgrading the system...${NC}"
apt update
apt upgrade -y

echo -e "${GREEN}System updated and upgraded successfully${NC}"
echo -e "${YELLOW}Note: If a reboot is required, please reboot manually after this script completes${NC}"
echo ""

# Check if reboot is required
if [ -f /var/run/reboot-required ]; then
    echo -e "${YELLOW}WARNING: System reboot is required. Please reboot after this script completes.${NC}"
    echo ""
fi

# Step 2: Install WireGuard
echo -e "${YELLOW}Step 2: Installing WireGuard...${NC}"
apt install -y wireguard

echo -e "${GREEN}WireGuard installed successfully${NC}"
echo ""

# Step 3: Generate WireGuard private and public keys
echo -e "${YELLOW}Step 3: Generating WireGuard private and public keys...${NC}"

# Create WireGuard directory if it doesn't exist
mkdir -p /etc/wireguard

# Generate private and public keys
wg genkey | tee /etc/wireguard/privatekey | wg pubkey | tee /etc/wireguard/publickey > /dev/null

# Set appropriate permissions on the private key
chmod 600 /etc/wireguard/privatekey

echo -e "${GREEN}Keys generated successfully${NC}"
echo -e "Private key saved to: /etc/wireguard/privatekey (permissions set to 600)"
echo -e "Public key saved to: /etc/wireguard/publickey"
echo ""

# Display the public key for reference
PUBLIC_KEY=$(cat /etc/wireguard/publickey)
echo -e "${GREEN}Your server's public key (save this for client setup):${NC}"
echo -e "${YELLOW}${PUBLIC_KEY}${NC}"
echo ""

# Step 4: Set up the initial WireGuard config file wg0.conf
echo -e "${YELLOW}Step 4: Creating WireGuard configuration file (wg0.conf)...${NC}"

PRIVATE_KEY=$(cat /etc/wireguard/privatekey)

# Create wg0.conf with the private key
cat > /etc/wireguard/wg0.conf << EOF
[Interface]
Address = 10.0.0.1/24, fd86:ea04:1111::1/64
ListenPort = 51820
PrivateKey = ${PRIVATE_KEY}
PostUp = iptables -A FORWARD -i %i -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE; ip6tables -A FORWARD -i %i -j ACCEPT; ip6tables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
PostDown = iptables -D FORWARD -i %i -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE; ip6tables -D FORWARD -i %i -j ACCEPT; ip6tables -t nat -D POSTROUTING -o eth0 -j MASQUERADE

# Add [Peer] sections below for each client
# Example:
# [Peer]
# PublicKey = <client_public_key>
# AllowedIPs = 10.0.0.2/32, fd86:ea04:1111::2/128
EOF

# Set appropriate permissions on wg0.conf
chmod 600 /etc/wireguard/wg0.conf

echo -e "${GREEN}Configuration file created at /etc/wireguard/wg0.conf (permissions set to 600)${NC}"
echo ""

# Enable IP forwarding
echo -e "${YELLOW}Enabling IP forwarding...${NC}"
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
echo "net.ipv6.conf.all.forwarding=1" >> /etc/sysctl.conf
sysctl -p > /dev/null

echo -e "${GREEN}IP forwarding enabled${NC}"
echo ""

# Step 5: Enable and start WireGuard service
echo -e "${YELLOW}Step 5: Enabling and starting WireGuard service...${NC}"

systemctl enable wg-quick@wg0
systemctl start wg-quick@wg0

# Check if service started successfully
if systemctl is-active --quiet wg-quick@wg0; then
    echo -e "${GREEN}WireGuard service enabled and started successfully${NC}"
    echo ""
    systemctl status wg-quick@wg0 --no-pager
else
    echo -e "${RED}Error: WireGuard service failed to start${NC}"
    echo "Please check the configuration and logs"
    exit 1
fi

echo ""
echo -e "${GREEN}=== WireGuard Server Setup Complete! ===${NC}"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "1. If a reboot is required, reboot your server"
echo "2. Save your server's public key shown above"
echo "3. Configure your client devices using the guide in README.md"
echo "4. Add client [Peer] sections to /etc/wireguard/wg0.conf"
echo "5. After adding clients, restart WireGuard: sudo systemctl restart wg-quick@wg0"
echo ""
echo -e "${YELLOW}Important files:${NC}"
echo "- Configuration: /etc/wireguard/wg0.conf"
echo "- Private key: /etc/wireguard/privatekey"
echo "- Public key: /etc/wireguard/publickey"
echo ""
echo -e "${YELLOW}Useful commands:${NC}"
echo "- Check status: sudo systemctl status wg-quick@wg0"
echo "- View active connections: sudo wg show"
echo "- Restart service: sudo systemctl restart wg-quick@wg0"
echo ""
