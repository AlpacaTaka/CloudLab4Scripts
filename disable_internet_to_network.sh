#!/bin/bash
# Uso: bash disableinternettonetwork.sh <VLAN_ID1> <CIDR1> <VLAN_ID2> <CIDR2> ...
# Ejemplo: ssh ubuntu@SERVER-3 bash -s < disableinternettonetwork.sh 100 192.168.0.0/24 200 192.168.2.0/24

while [ "$#" -ge 2 ]; do
    VLAN_ID=$1
    CIDR=$2
    GW_IFACE="gw_vlan${VLAN_ID}"

    sudo iptables -t nat -D POSTROUTING -s $CIDR -o ens3 -j MASQUERADE
    sudo iptables -D FORWARD -i $GW_IFACE -o ens3 -j ACCEPT
    echo "OK: Internet deshabilitado para VLAN $VLAN_ID"

    shift 2
done

# Eliminar conntrack solo si ya no hay más reglas MASQUERADE
REMAINING=$(sudo iptables -t nat -L POSTROUTING -n | grep -c "MASQUERADE")
if [ "$REMAINING" -eq 0 ]; then
    sudo iptables -D FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
    echo "OK: Regla conntrack eliminada (sin más VLANs con internet)"
else
    echo "AVISO: Regla conntrack conservada ($REMAINING VLANs aún tienen internet)"
fi

