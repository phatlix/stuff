#!/usr/bin/env bash

#  ┌───────────────────────┐
#  │                       │
#  │     - WG_SETUP -      │
#  │    REV: 2025022801    │
#  │                       │
#  │     Yours truly,      │
#  │        phatlix        │
#  │                       │
#  └───────────────────────┘

# PURPOSE: 
#   - To install wireguard as either a server and client
#   - To present a interactive list of options for the installs
#   - To include everything required for a working wireguard vpn
#
# TODO:
#   - Swap out if conditions in favor of case
#   - Add option to produce client configs (from the server side)
#   - Include checks for an existing setup
#   - Include cli install options
#   - Include a backup and uninstall option
#
# EXTRA TIME:
#   - Include error/debug traps and logging
#   - Borrow ideas and code from other Github projects that have
#     already got this stuff all figured out and broaden my horizon.


# ----- OPTIONS -----


qna() {
  printf "${NON}\n"
  read -p "$(echo -e ${WHT}" INSTALL WIREGURARD    [y/N]  : "${BLU})" INSTWG
  INSTWG=${INSTWG:-n}

  read -p "$(echo -e ${WHT}" INSTALLING A SERVER OR CLIENT    [s/C]  : "${BLU})" SERVCLNT
  SERVCLNT=${SERVCLNT:-c}

  if [[ "$SERVCLNT" == "c" || "$SERVCLNT" == "C" ]]; then
    read -p "$(echo -e ${WHT}" SERVER PUBLIC KEY : "${BLU})" SRVKEY

    read -p "$(echo -e ${WHT}" SERVER WAN IP    [1.2.3.4]  : "${BLU})" SRVWAN
    SRVWAN=${SRVWAN:-1.2.3.4}

    read -p "$(echo -e ${WHT}" SERVER PEER NETWORK IP & CIDR    [10.9.0.1/24]  : "${BLU})" SRVIP
    SRVIP=${SRVIP:-10.9.0.1/24}

    read -p "$(echo -e ${WHT}" CLIENT PEER IP & CIDR    [10.9.0.2/32]  : "${BLU})" CLNTIP
    CLNTIP=${CLNTIP:-10.9.0.2/32}

    read -p "$(echo -e ${WHT}" ALLOWED NETWORKS    [10.0.0.0/24]  : "${BLU})" ALLNET
    ALLNET=${ALLNET:-10.0.0.0/24}

    read -p "$(echo -e ${WHT}" DNS SERVER IP    [10.0.0.6]  : "${BLU})" DNSIP
    DNSIP=${DNSIP:-10.0.0.6}

    read -p "$(echo -e ${WHT}" DNS SEARCH DOMAIN    [skullmedia.lan]  : "${BLU})" DNSSD
    DNSSD=${DNSSD:-skullmedia.lan}

    read -p "$(echo -e ${WHT}" KEEP ALIVE    [25]  : "${BLU})" KALIVE
    KALIVE=${KALIVE:-25}
  fi

  if [[ "$SERVCLNT" == "s" || "$SERVCLNT" == "S" ]]; then
    read -p "$(echo -e ${WHT}" SERVER PEER NETWORK IP & CIDR    [10.9.0.1/24]  : "${BLU})" SRVIP
    SRVIP=${SRVIP:-10.9.0.1/24}
  fi

  read -p "$(echo -e ${WHT}" LISTEN PORT    [51820]  : "${BLU})" LPORT
  LPORT=${LPORT:-51820}

  read -p "$(echo -e ${WHT}" INTERFACE NAME    [wg0]  : "${BLU})" INTNM
  INTNM=${INTNM:-wg0}
  printf "${NON}\n"
}


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

qna

WGPATH="/etc/wireguard"
SRVINT=$(ip route show to default | grep -Eo "dev\s*[[:alnum:]]+" | sed 's/dev\s//g');
SRVNET=$(ipcalc ${SRVIP} | awk '/Network:/ {print $2}');
SRVNETIP=$(ipcalc ${SRVIP} | awk '/Address:/ {print $2}');

if [[ "$INSTWG" == "y" || "$INSTWG" == "Y" ]]; then
  printf "${BLU}Updating system and installing wireguard.\n\
  ${GRY}This might take a hot second...${NON}\n"
  dnf install elrepo-release epel-release -y -q
  dnf upgrade -y -q
  dnf install kmod-wireguard wireguard-tools -y -q
  dnf update -y -q
fi

mkdir -p ${WGPATH}/helper
touch ${WGPATH}/${INTNM} && chmod 600 ${WGPATH}/${INTNM}
wg genkey > ${WGPATH}/${INTNM}
cat ${WGPATH}/${INTNM} | wg pubkey > ${WGPATH}/${INTNM}.pub

PKEY=$(cat ${WGPATH}/${INTNM});
SKEY=$(cat ${WGPATH}/${INTNM}.pub);

if [[ "$SERVCLNT" == "c" || "$SERVCLNT" == "C" ]]; then
cat > ${WGPATH}/${INTNM}.conf << EOF
[Interface]
PrivateKey = ${PKEY}
Address = ${CLNTIP}
ListenPort = ${LPORT}
DNS = ${DNSIP}, ${DNSSD}
PostUp = ${WGPATH}/helper/wg-fw-add.sh
PostDown = ${WGPATH}/helper/wg-fw-del.sh

[Peer]
PublicKey = ${SRVKEY}
AllowedIPs = ${SRVNETIP}/32, ${ALLNET}
Endpoint = ${SRVWAN}:${LPORT}
PersistentKeepalive = ${KALIVE}
EOF
fi

if [[ "$SERVCLNT" == "s" || "$SERVCLNT" == "S" ]]; then
cat > ${WGPATH}/${INTNM}.conf << EOF
[Interface]
PrivateKey = ${PKEY}
Address = ${SRVIP}
ListenPort = ${LPORT}
PostUp = ${WGPATH}/helper/wg-fw-add.sh
PostDown = ${WGPATH}/helper/wg-fw-del.sh
EOF
fi

cat > /etc/sysctl.d/10-wireguard.conf << "EOF"
# IP FORWARDING
net.ipv4.ip_forward=1
EOF

sysctl -q -p /etc/sysctl.d/10-wireguard.conf

cat > ${WGPATH}/helper/wg-fw-add.sh << EOF
#!/bin/bash
IPT="/sbin/iptables"
 
IN_FACE="${SRVINT}"     # NIC connected to the internet
WG_FACE="${INTNM}"      # WG NIC 
SUB_NET="${SRVNET}"     # WG IPv4 sub/net aka CIDR
WG_PORT="${LPORT}"      # WG udp port
 
\$IPT -t nat -I POSTROUTING 1 -s \$SUB_NET -o \$IN_FACE -j MASQUERADE
\$IPT -I INPUT 1 -i \$WG_FACE -j ACCEPT
\$IPT -I FORWARD 1 -i \$IN_FACE -o \$WG_FACE -j ACCEPT
\$IPT -I FORWARD 1 -i \$WG_FACE -o \$IN_FACE -j ACCEPT
\$IPT -I INPUT 1 -i \$IN_FACE -p udp --dport \$WG_PORT -j ACCEPT

EOF

cat > ${WGPATH}/helper/wg-fw-del.sh << EOF
#!/bin/bash
IPT="/sbin/iptables"
 
IN_FACE="${SRVINT}"     # NIC connected to the internet
WG_FACE="${INTNM}"      # WG NIC 
SUB_NET="${SRVNET}"     # WG IPv4 sub/net aka CIDR
WG_PORT="${LPORT}"      # WG udp port
 
\$IPT -t nat -D POSTROUTING -s \$SUB_NET -o \$IN_FACE -j MASQUERADE
\$IPT -D INPUT -i \$WG_FACE -j ACCEPT
\$IPT -D FORWARD -i \$IN_FACE -o \$WG_FACE -j ACCEPT
\$IPT -D FORWARD -i \$WG_FACE -o \$IN_FACE -j ACCEPT
\$IPT -D INPUT -i \$IN_FACE -p udp --dport \$WG_PORT -j ACCEPT
 
EOF

chmod +x ${WGPATH}/helper/*.sh

if [[ "$SERVCLNT" == "c" || "$SERVCLNT" == "C" ]]; then
  printf "\n \
  ${GRY}--- ${YLW}RUN THIS ON THE WG SERVER TO ADD THE CLIENT ${GRY}---${WHT}\n \
  wg set ${INTNM} peer \"${SKEY}\" allowed-ips ${CLNTIP} persistent-keepalive ${KALIVE}\n \
  wg-quick save ${INTNM}\n\n \
  ${GRY}--- ${YLW}START AND STOP SERVICE COMMANDS ${GRY}---${WHT}\n \
  systemctl start wg-quick@${INTNM}\n \
  systemctl stop wg-quick@${INTNM}\n\n \
  ${GRY}--- ${YLW}START AND STOP CLI COMMANDS ${GRY}---${WHT}\n \
  wg-quick up ${INTNM}\n \
  wg-quick down ${INTNM}\n\n \
  ${GRY}--- ${YLW}TO VIEW WG CONFIG ${GRY}---${WHT}\n \
  wg\n${NON} \
  \n"
fi

if [[ "$SERVCLNT" == "s" || "$SERVCLNT" == "S" ]]; then
  printf "\n \
  ${GRY}--- ${YLW}INFO NEEDED FOR CLIENT CONFIGS ${GRY}---\n \
  ${CYN}SERVER PUBLIC KEY: ${WHT}${SKEY}\n \
  ${CYN}SERVER WAN IP: ${WHT}$(curl -s https://ipinfo.io/ip)\n \
  ${CYN}SERVER WG IP: ${WHT}${SRVIP}\n\n \
  ${GRY}--- ${YLW}START AND STOP SERVICE COMMANDS ${GRY}---${WHT}\n \
  systemctl start wg-quick@${INTNM}\n \
  systemctl stop wg-quick@${INTNM}\n\n \
  ${GRY}--- ${YLW}START AND STOP CLI COMMANDS ${GRY}---${WHT}\n \
  wg-quick up ${INTNM}\n \
  wg-quick down ${INTNM}\n\n \
  ${GRY}--- ${YLW}TO VIEW WG CONFIG ${GRY}---${WHT}\n \
  wg\n${NON} \
  \n"
fi

exit 0
