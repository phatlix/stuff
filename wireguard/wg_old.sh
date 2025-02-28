#!/usr/bin/env bash

#
# PURPOSE: creates wireguard install scripts
#          for both server and client.
#

cat > wg_server << "WGSERVER"
#!/usr/bin/env bash

# ----- SERVER SIDE INSTALL INFO-----

SERVER_WG_IP="10.9.0.1/24"  #WG NETWORK SERVER IP AND CIDR
LISTEN_PORT="51820"         #WG LISTEN PORT


# ----- INSTALL -----

GRY="\e[90m"   # Gray
RED="\e[91m"   # Red
GRN="\e[92m"   # Green
YLW="\e[93m"   # Yellow
BLU="\e[94m"   # Blue
PRP="\e[95m"   # Purple
CYN="\e[96m"   # Cyan
WHT="\e[97m"   # White
NON="\e[0m"    # Reset

printf "${BLU}Updating system and installing wireguard.\n\
${GRY}This might take a hot second...${NON}\n"
dnf install elrepo-release epel-release -y -q
dnf upgrade -y -q
dnf install kmod-wireguard wireguard-tools -y -q
dnf update -y -q

WGPATH="/etc/wireguard"

mkdir -p ${WGPATH}/helper
touch ${WGPATH}/wg0 && chmod 600 ${WGPATH}/wg0
wg genkey > ${WGPATH}/wg0
cat ${WGPATH}/wg0 | wg pubkey > ${WGPATH}/wg0.pub

PKEY=$(cat /etc/wireguard/wg0);
SKEY=$(cat /etc/wireguard/wg0.pub);

cat > /etc/wireguard/wg0.conf << EOF
[Interface]
PrivateKey = ${PKEY}
Address = ${SERVER_WG_IP}
ListenPort = ${LISTEN_PORT}
PostUp = ${WGPATH}/helper/wg-fw-add.sh
PostDown = ${WGPATH}/helper/wg-fw-del.sh
EOF

cat > /etc/sysctl.d/10-wireguard.conf << "EOF"
# IP FORWARDING
net.ipv4.ip_forward=1
#net.ipv6.conf.all.forwarding=1
EOF
sysctl -q -p /etc/sysctl.d/10-wireguard.conf

SRVINT=$(ip -br l | awk '$1 !~ "lo|vir|wl" { print $1}');
SRVNET=$(ipcalc ${SERVER_WG_IP} | awk '/Network/ {print $2}');

cat > ${WGPATH}/helper/wg-fw-add.sh << EOF
#!/bin/bash
IPT="/sbin/iptables"
#IPT6="/sbin/ip6tables"          
 
IN_FACE="${SRVINT}"          # NIC connected to the internet
WG_FACE="wg0"             # WG NIC 
SUB_NET="${SRVNET}"     # WG IPv4 sub/net aka CIDR
WG_PORT="${LISTEN_PORT}"           # WG udp port
#SUB_NET_6="fd42:42:42:42::/112"   # WG IPv6 sub/net
 
## IPv4 ##
\$IPT -t nat -I POSTROUTING 1 -s \$SUB_NET -o \$IN_FACE -j MASQUERADE
\$IPT -I INPUT 1 -i \$WG_FACE -j ACCEPT
\$IPT -I FORWARD 1 -i \$IN_FACE -o \$WG_FACE -j ACCEPT
\$IPT -I FORWARD 1 -i \$WG_FACE -o \$IN_FACE -j ACCEPT
\$IPT -I INPUT 1 -i \$IN_FACE -p udp --dport \$WG_PORT -j ACCEPT
 
## IPv6 ##
#\$IPT6 -t nat -I POSTROUTING 1 -s \$SUB_NET_6 -o \$IN_FACE -j MASQUERADE
#\$IPT6 -I INPUT 1 -i \$WG_FACE -j ACCEPT
#\$IPT6 -I FORWARD 1 -i \$IN_FACE -o \$WG_FACE -j ACCEPT
#\$IPT6 -I FORWARD 1 -i \$WG_FACE -o \$IN_FACE -j ACCEPT
EOF

cat > ${WGPATH}/helper/wg-fw-del.sh << EOF
#!/bin/bash
IPT="/sbin/iptables"
#IPT6="/sbin/ip6tables"          
 
IN_FACE="${SRVINT}"          # NIC connected to the internet
WG_FACE="wg0"             # WG NIC 
SUB_NET="${SRVNET}"     # WG IPv4 sub/net aka CIDR
WG_PORT="${LISTEN_PORT}"           # WG udp port
#SUB_NET_6="fd42:42:42:42::/112"   # WG IPv6 sub/net
 
## IPv4 ##
\$IPT -t nat -D POSTROUTING -s \$SUB_NET -o \$IN_FACE -j MASQUERADE
\$IPT -D INPUT -i \$WG_FACE -j ACCEPT
\$IPT -D FORWARD -i \$IN_FACE -o \$WG_FACE -j ACCEPT
\$IPT -D FORWARD -i \$WG_FACE -o \$IN_FACE -j ACCEPT
\$IPT -D INPUT -i \$IN_FACE -p udp --dport \$WG_PORT -j ACCEPT
 
## IPv6 ##
#\$IPT6 -t nat -D POSTROUTING -s \$SUB_NET_6 -o \$IN_FACE -j MASQUERADE
#\$IPT6 -D INPUT -i \$WG_FACE -j ACCEPT
#\$IPT6 -D FORWARD -i \$IN_FACE -o \$WG_FACE -j ACCEPT
#\$IPT6 -D FORWARD -i \$WG_FACE -o \$IN_FACE -j ACCEPT
EOF

chmod +x ${WGPATH}/helper/*.sh

printf "\n \
${GRY}--- ${YLW}INFO NEEDED FOR CLIENT CONFIGS ${GRY}---\n \
${CYN}SERVER PUBLIC KEY: ${WHT}${SKEY}\n \
${CYN}SERVER WAN IP: ${WHT}$(curl -s https://ipinfo.io/ip)\n \
${CYN}SERVER WG IP: ${WHT}${SERVER_WG_IP}\n\n \
${GRY}--- ${YLW}START AND STOP SERVICE COMMANDS ${GRY}---${WHT}\n \
systemctl start wg-quick@wg0\n \
systemctl stop wg-quick@wg0\n\n \
${GRY}--- ${YLW}START AND STOP CLI COMMANDS ${GRY}---${WHT}\n \
wg-quick up wg0\n \
wg-quick down wg0\n\n \
${GRY}--- ${YLW}TO VIEW WG CONFIG ${GRY}---${WHT}\n \
wg\n${NON} \
\n"

exit 0

WGSERVER

cat > wg_client << "WGCLIENT"
#!/usr/bin/env bash

# ----- PEER SIDE INSTALL -----

SERVER_PUBLIC_KEY="xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx" #WG SERVER PUBLIC KEY
SERVER_WAN_IP="1.2.3.4"                                          #WG SERVER WAN IP
CLIENT_WG_IP="10.9.0.2/32"                                       #WG NETWORK PEER IP AND CIDR
ALLOWED_NET="10.9.0.1/32, 10.0.0.0/24"                           #ALLOWED NETWORKS OR IPS (INCLUDE WG NETWORK SERVER IP)
LISTEN_PORT="51820"                                              #WG LISTEN PORT
DNS_INFO="10.0.0.2, domain.lan"                                  #DNS SERVER AND SEARCH DOMAIN (REMOTE NETWORK RESOLUTION)

# ----- INSTALL -----

GRY="\e[90m"   # Gray
RED="\e[91m"   # Red
GRN="\e[92m"   # Green
YLW="\e[93m"   # Yellow
BLU="\e[94m"   # Blue
PRP="\e[95m"   # Purple
CYN="\e[96m"   # Cyan
WHT="\e[97m"   # White
NON="\e[0m"    # Reset

printf "${BLU}Updating system and installing wireguard.\n\
${GRY}This might take a hot second...${NON}\n"
dnf install elrepo-release epel-release -y -q
dnf upgrade -y -q
dnf install kmod-wireguard wireguard-tools -y -q
dnf update -y -q

WGPATH="/etc/wireguard"

mkdir -p ${WGPATH}/helper
touch ${WGPATH}/wg0 && chmod 600 ${WGPATH}/wg0
wg genkey > ${WGPATH}/wg0
cat ${WGPATH}/wg0 | wg pubkey > ${WGPATH}/wg0.pub

PKEY=$(cat /etc/wireguard/wg0);
SKEY=$(cat /etc/wireguard/wg0.pub);

cat > /etc/wireguard/wg0.conf << EOF
[Interface]
PrivateKey = ${PKEY}
ListenPort = ${LISTEN_PORT}
Address = ${CLIENT_WG_IP}
DNS = ${DNS_INFO}

[Peer]
PublicKey = ${SERVER_PUBLIC_KEY}
AllowedIPs = ${ALLOWED_NET}
Endpoint = ${SERVER_WAN_IP}:${LISTEN_PORT}
PersistentKeepalive = 25
EOF

printf "\n \
${GRY}--- ${YLW}RUN THIS ON THE WG SERVER TO ADD THE CLIENT ${GRY}---${WHT}\n \
wg set wg0 peer \"${SKEY}\" allowed-ips ${CLIENT_WG_IP}\n \
wg-quick save wg0\n\n \
${GRY}--- ${YLW}START AND STOP SERVICE COMMANDS ${GRY}---${WHT}\n \
systemctl start wg-quick@wg0\n \
systemctl stop wg-quick@wg0\n\n \
${GRY}--- ${YLW}START AND STOP CLI COMMANDS ${GRY}---${WHT}\n \
wg-quick up wg0\n \
wg-quick down wg0\n\n \
${GRY}--- ${YLW}TO VIEW WG CONFIG ${GRY}---${WHT}\n \
wg\n${NON} \
\n"

exit 0

WGCLIENT

chmod +x wg_*

exit 0
