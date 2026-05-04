#!/bin/bash
# Uso: bash internettonetwork.sh <VLAN_ID1> <CIDR1> [VLAN_ID2] [CIDR2] ...
# Ejemplo 1 VLAN:   ssh ubuntu@SERVER-3 bash -s < internettonetwork.sh 100 192.168.0.0/24
# Ejemplo 2 VLANs:  ssh ubuntu@SERVER-3 bash -s < internettonetwork.sh 100 192.168.0.0/24 200 192.168.2.0/24

if [ "$#" -lt 2 ] || [ $(( $# % 2 )) -ne 0 ]; then
    echo "ERROR: Debes pasar pares de VLAN_ID y CIDR."
    echo "Uso: internettonetwork.sh <VLAN_ID1> <CIDR1> [VLAN_ID2] [CIDR2] ..."
    exit 1
fi

# Verificar que br-int existe
if ! sudo ovs-vsctl br-exists br-int; then
    echo "ERROR: El bridge br-int no existe. Ejecuta headnodeinit.sh primero."
    exit 1
fi

sudo sysctl -w net.ipv4.ip_forward=1

while [ "$#" -ge 2 ]; do
    VLAN_ID=$1
    CIDR=$2
    GW_IFACE="gw_vlan${VLAN_ID}"

    # Verificar que la interfaz gateway existe
    if ! ip link show "$GW_IFACE" &>/dev/null; then
        echo "ERROR: La interfaz '$GW_IFACE' no existe. ¿Creaste la red con createnetworkvlan.sh? Saltando..."
        shift 2
        continue
    fi

    # Agregar NAT solo si no existe
    if ! sudo iptables -t nat -C POSTROUTING -s $CIDR -o ens3 -j MASQUERADE 2>/dev/null; then
        sudo iptables -t nat -A POSTROUTING -s $CIDR -o ens3 -j MASQUERADE
        echo "OK: Regla NAT agregada para $CIDR."
    else
        echo "AVISO: Regla NAT para $CIDR ya existe."
    fi

    # Agregar regla FORWARD solo si no existe
    if ! sudo iptables -C FORWARD -i $GW_IFACE -o ens3 -j ACCEPT 2>/dev/null; then
        sudo iptables -A FORWARD -i $GW_IFACE -o ens3 -j ACCEPT
        echo "OK: Regla FORWARD $GW_IFACE -> ens3 agregada."
    else
        echo "AVISO: Regla FORWARD $GW_IFACE -> ens3 ya existe."
    fi

    echo "OK: Internet habilitado para VLAN $VLAN_ID ($CIDR)."
    shift 2
done

# Agregar conntrack solo si no existe (es una regla global, se agrega una sola vez)
if ! sudo iptables -C FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT 2>/dev/null; then
    sudo iptables -A FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
    echo "OK: Regla conntrack ESTABLISHED,RELATED agregada."
else
    echo "AVISO: Regla conntrack ya existe, no se duplica."
fi