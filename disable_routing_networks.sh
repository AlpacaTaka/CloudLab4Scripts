#!/bin/bash
# Uso: bash disableroutingnetworks.sh <VLAN_ID_1> <VLAN_ID_2>
# Ejemplo: ssh ubuntu@SERVER-3 bash -s < disableroutingnetworks.sh 100 200
# Elimina exactamente las reglas creadas por routingnetworks.sh (usa -D en lugar de -A)

VLAN1=$1
VLAN2=$2
GW1="gw_vlan${VLAN1}"
GW2="gw_vlan${VLAN2}"

sudo iptables -D FORWARD -i $GW1 -o $GW2 -j ACCEPT
sudo iptables -D FORWARD -i $GW2 -o $GW1 -j ACCEPT