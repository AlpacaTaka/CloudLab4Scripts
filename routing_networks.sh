#!/bin/bash
# Uso: bash routingnetworks.sh <VLAN_ID_1> <VLAN_ID_2>
# Ejemplo: ssh ubuntu@SERVER-3 bash -s < routingnetworks.sh 100 200
# Permite tráfico bidireccional entre las dos VLANs via iptables FORWARD

VLAN1=$1
VLAN2=$2

# Validar parámetros
if [ -z "$VLAN1" ] || [ -z "$VLAN2" ]; then
    echo "ERROR: Faltan parámetros. Uso: routingnetworks.sh <VLAN_ID_1> <VLAN_ID_2>"
    exit 1
fi

# Verificar que no sean la misma VLAN
if [ "$VLAN1" == "$VLAN2" ]; then
    echo "ERROR: Las dos VLANs no pueden ser iguales."
    exit 1
fi

GW1="gw_vlan${VLAN1}"
GW2="gw_vlan${VLAN2}"

# Verificar que las interfaces gateway existen
if ! ip link show $GW1 &>/dev/null; then
    echo "ERROR: La interfaz '$GW1' no existe. ¿Creaste la red con createnetworkvlan.sh?"
    exit 1
fi

if ! ip link show $GW2 &>/dev/null; then
    echo "ERROR: La interfaz '$GW2' no existe. ¿Creaste la red con createnetworkvlan.sh?"
    exit 1
fi

# Agregar reglas solo si no existen (evita duplicados)
if ! sudo iptables -C FORWARD -i $GW1 -o $GW2 -j ACCEPT 2>/dev/null; then
    sudo iptables -A FORWARD -i $GW1 -o $GW2 -j ACCEPT
    echo "OK: Regla FORWARD $GW1 -> $GW2 agregada."
else
    echo "AVISO: Regla $GW1 -> $GW2 ya existe."
fi

if ! sudo iptables -C FORWARD -i $GW2 -o $GW1 -j ACCEPT 2>/dev/null; then
    sudo iptables -A FORWARD -i $GW2 -o $GW1 -j ACCEPT
    echo "OK: Regla FORWARD $GW2 -> $GW1 agregada."
else
    echo "AVISO: Regla $GW2 -> $GW1 ya existe."
fi

echo "---------------------------------------"
echo "OK: Ruteo habilitado entre VLAN $VLAN1 y VLAN $VLAN2."
echo "    $GW1 <-> $GW2"
echo "---------------------------------------"