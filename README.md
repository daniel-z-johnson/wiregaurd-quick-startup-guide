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
8. 
