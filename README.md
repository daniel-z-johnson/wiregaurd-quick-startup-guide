# wireguard-quick-startup-guide

## Server Setup
1. Get a server, services you can use include Linode, Digital Ocean, and many others
2. You only need a very small server, I chose the cheapest one that was only $5 a month when I did my setup and it worked fine
3. I used Ubuntu for my OS (Ubuntu 20.04 or later recommended)
4. __Secure the Server__, look at a guide to do this, it includes updating, setting up auto update, preventing root login, no password login, and many other steps
5. Install WireGuard<br>
  `sudo apt update && sudo apt install wireguard`
6. Enable IP forwarding
    1. Edit sysctl configuration: `sudo vim /etc/sysctl.conf`
    2. Run the following
         ```
         echo net.ipv4.ip_forward=1 | tee -a /etc/sysctl.conf
         echo net.ipv6.conf.all.forwarding=1 | tee -a /etc/sysctl.conf
         ```
    3. Apply the changes: `sudo sysctl -p`
7. Generate private and public keys for WireGuard:<br>
`sudo wg genkey | sudo tee /etc/wireguard/privatekey | sudo wg pubkey | sudo tee /etc/wireguard/publickey`
8. Create and edit wg0.conf: `sudo vim /etc/wireguard/wg0.conf` and add the following (replace `<the private key generated above>` with the actual private key from step 7)
```
[Interface]
Address = 10.0.0.1/24, fd86:ea04:1111::1/64
ListenPort = 51820
PrivateKey = <the private key generated above>
PostUp = iptables -A FORWARD -i %i -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE; ip6tables -A FORWARD -i %i -j ACCEPT; ip6tables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
PostDown = iptables -D FORWARD -i %i -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE; ip6tables -D FORWARD -i %i -j ACCEPT; ip6tables -t nat -D POSTROUTING -o eth0 -j MASQUERADE
```
9. Secure WireGuard files by restricting permissions:<br>
`sudo chmod 600 /etc/wireguard/{privatekey,wg0.conf}`
10. Done with the server for now (you'll come back to it in the Client Setup section)

**Note:** Keep the public key from step 7 handy - you'll need it during client setup.
## Client Setup
1. Install WireGuard on your client machine (I am using Pop OS):<br>
`sudo apt install wireguard`
2. Generate public and private keys for the client:<br>
`wg genkey | tee ~/client_privatekey | wg pubkey > ~/client_publickey`
3. Create client configuration file: `sudo vim /etc/wireguard/wg0.conf`<br>
(You can use any name not just `wg0.conf`, it may make more sense to have a meaningful name)
4. Add the following to the configuration file (replace the placeholders with actual values)
```
[Interface]
PrivateKey = <private key gen for client above>
Address = 10.0.0.2/24, fd86:ea04:1111::2/64
DNS = 1.1.1.1, 2606:4700:4700::1111

[Peer]
PublicKey = <pub key generated on the server>
Endpoint = <ip or domain name of server>:51820
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
```
5. Secure the configuration file:<br>
`sudo chmod 600 /etc/wireguard/wg0.conf`

### Configure the Server to Accept the Client
6. __On the server__, edit the WireGuard configuration
7. `sudo vim /etc/wireguard/wg0.conf` and add the following peer section, keep what has been added already the same
```
[Interface]
keep everything the same

[Peer]
PublicKey = <Pub key generated on the client and not the server>
AllowedIPs = 10.0.0.2/32, fd86:ea04:1111::2/128
```
8. Still on the server, enable and start the WireGuard service:
```
sudo systemctl enable wg-quick@wg0
sudo systemctl start wg-quick@wg0
sudo systemctl status wg-quick@wg0
```
9. Make sure the service is running successfully, then go back to the client

### Test the Connection
10. __On the client machine__, check your current IP addresses:
```
curl -4 ifconfig.co
curl -6 ifconfig.co
```
11. Make a note of the results (these are your current IPs without VPN)
12. Start the WireGuard connection on the client:<br>
`sudo wg-quick up wg0`
13. Rerun the curl commands and the IPs should have changed to your server's IP addresses
14. To stop the VPN connection, run __on the client__:<br>
`sudo wg-quick down wg0`

### Optional: Auto-start WireGuard on Client
If you want WireGuard to start automatically on boot on the client:
```
sudo systemctl enable wg-quick@wg0
```
### Debugging Issues
#### AWS ens5
- `eth0` may not be the network interface
- run `ip link show` to see the network interfaces, it may be something like `ens5`
- in `wg0.conf` replace `eth0` with `ens5`
