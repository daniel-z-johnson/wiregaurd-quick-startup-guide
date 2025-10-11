# wiregaurd-quick-startup-guide

## Server setup
1. Get a server, services you can use include Linode, Digital Ocean, and many others
2. You only need a very small server, I choose the cheepest one that was only $5 a mounth when I did my setup and it worked fine
3. I used Ubuntu for my OS
4. __Secure the Sever__, look at a guide to do this, it includes updating, setting up auto update, preventing root login, no password login, and many other steps
5. install wire gaurd<br>
  `apt install wiregaurd`
6. enable ip passthrough
    1. `vim /ect/sysctl.conf`
    2. uncomment these line to enable packet forwarding
         - `net.ipv6.conf.all.forwarding=1`
         - `net.ipv4.ip_forward=1`
    4. run `sysctl -p`
7. run `wg genkey | tee /etc/wireguard/privatekey | wg pubkey > /etc/wireguard/publickey` to generate private and public keys for wiregaurd
8. create and edit wg0.cong `vim /etc/wiregaurd/wg0.conf` and add the following
```
[Interface]
Address = 10.0.0.1/24, fd86:ea04:1111::1/64
ListenPort = 51820
PrivateKey = <the private key generated above>
PostUp = iptables -A FORWARD -i %i -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE; ip6tables -A FORWARD -i %i -j ACCEPT; ip6tables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
PostDown = iptables -D FORWARD -i %i -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE; ip6tables -D FORWARD -i %i -j ACCEPT; ip6tables -t nat -D POSTROUTING -o eth0 -j MASQUERADE
```
9. Secure wiregaurd files<br>
`chmod 600 /etc/wireguard/{privatekey,wg0.conf}`
10. Done with the server for now
## Client set up
1. Install wiregaurd, I am using Pop OS `sudo apt install wiregaurd`
2. gen pub and private key<br>
`wg genkey | tee ~/client_privatekey | wg pubkey > ~/client_publickey`
3. Create file `udo vim /etc/wireguard/wg0.conf`, you can use any name not just `wg0.conf`, it may make more sense to have a meniful name
4. Add the following to the conf file
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
5. secure conf file `sudo chmod 600 /etc/wireguard/wg0.conf`
6. __On the server__
7. `vim /etc/wiregaurd/wg0.conf` and add the follow, keep what have been added already the same
```
[Interface]
keep everything the same

[Peer]
PublicKey = <Pub key generated on the client and not the server>
AllowedIPs = 10.0.0.2/32, fd86:ea04:1111::2/128
```
8. Still on the server run the following 
```
systemctl enable wg-quick@wg0
systemctl status wg-quick@wg0
systemctl start wg-quick@wg0
systemctl status wg-quick@wg0
```
9. Make sure it is running, go back to the client, my laptop in my case
10. __On your machine__ or __on the client__
11. run the following
```
curl -4 ifconfig.co
curl -6 ifconfig.co
```
12. make a note of the results
13. run `sudo wg-quick up wg0`
14. Rerun the curl cmds and the ips should have changed
15. To stop the connect run __on the client__ `sudo wg-quick down wg0`
