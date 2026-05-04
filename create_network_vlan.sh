#!/bin/bash
# Uso: bash createnetworkvlan.sh <VLAN_ID> <CIDR> <dhcp|nodhcp> [dhcp_start] [dhcp_end]
# Ejemplo sin DHCP:  ssh ubuntu@SERVER-3 bash -s < createnetworkvlan.sh 100 192.168.0.0/24 nodhcp
# Ejemplo con DHCP:  ssh ubuntu@SERVER-3 bash -s < createnetworkvlan.sh 200 192.168.2.0/24 dhcp 192.168.2.11 192.168.2.15

VLAN_ID=$1
CIDR=$2
DHCP=$3
DHCP_START=$4
DHCP_END=$5

# Validar parámetros obligatorios
if [ -z "$VLAN_ID" ] || [ -z "$CIDR" ] || [ -z "$DHCP" ]; then
    echo "ERROR: Faltan parámetros. Uso: createnetworkvlan.sh <VLAN_ID> <CIDR> <dhcp|nodhcp> [dhcp_start] [dhcp_end]"
    exit 1
fi

# Validar que si es dhcp se pasen los rangos
if [ "$DHCP" == "dhcp" ] && ([ -z "$DHCP_START" ] || [ -z "$DHCP_END" ]); then
    echo "ERROR: Con dhcp debes indicar dhcp_start y dhcp_end."
    exit 1
fi

# Verificar que br-int existe
if ! sudo ovs-vsctl br-exists br-int; then
    echo "ERROR: El bridge br-int no existe. Ejecuta headnodeinit.sh primero."
    exit 1
fi

NETWORK=$(echo $CIDR | cut -d'/' -f1)
PREFIX=$(echo $CIDR | cut -d'/' -f2)
BASE=$(echo $NETWORK | cut -d'.' -f1-3)
GW_IP="${BASE}.1/${PREFIX}"
GW_ADDR="${BASE}.1"
DHCP_IP="${BASE}.2/${PREFIX}"
PORT_NAME="gw_vlan${VLAN_ID}"

# Crear puerto gateway en OvS
if ! sudo ovs-vsctl list-ports br-int | grep -q "^${PORT_NAME}$"; then
    sudo ovs-vsctl add-port br-int $PORT_NAME tag=${VLAN_ID} -- set interface $PORT_NAME type=internal
    echo "OK: Puerto gateway '$PORT_NAME' creado en br-int con tag VLAN $VLAN_ID."
else
    echo "AVISO: Puerto '$PORT_NAME' ya existe en br-int, se reutilizará."
fi

sudo ip addr add $GW_IP dev $PORT_NAME 2>/dev/null || echo "AVISO: IP $GW_IP ya asignada a $PORT_NAME."
sudo ip link set dev $PORT_NAME up
echo "OK: Gateway $PORT_NAME levantado con IP $GW_ADDR."

if [ "$DHCP" == "dhcp" ]; then
    NS_NAME="ns-dhcp-vlan${VLAN_ID}"
    VETH_NS="dhcp_v${VLAN_ID}"
    VETH_OVS="dhcp_v${VLAN_ID}_ovs"

    # Crear namespace
    if ! sudo ip netns list | grep -q "^${NS_NAME}"; then
        sudo ip netns add $NS_NAME
        echo "OK: Namespace '$NS_NAME' creado."
    else
        echo "AVISO: Namespace '$NS_NAME' ya existe, se reutilizará."
    fi

    # Crear par veth
    if ! ip link show $VETH_OVS &>/dev/null; then
        sudo ip link add $VETH_NS type veth peer name $VETH_OVS
        echo "OK: Par veth '$VETH_NS' <-> '$VETH_OVS' creado."
    else
        echo "AVISO: Par veth '$VETH_OVS' ya existe, se reutilizará."
    fi

    # Agregar extremo OvS al bridge
    if ! sudo ovs-vsctl list-ports br-int | grep -q "^${VETH_OVS}$"; then
        sudo ovs-vsctl add-port br-int $VETH_OVS tag=${VLAN_ID}
        echo "OK: Puerto '$VETH_OVS' agregado al br-int con tag VLAN $VLAN_ID."
    else
        echo "AVISO: Puerto '$VETH_OVS' ya está en br-int."
    fi
    sudo ip link set dev $VETH_OVS up

    # Mover extremo al namespace
    sudo ip link set $VETH_NS netns $NS_NAME 2>/dev/null || echo "AVISO: '$VETH_NS' ya está en el namespace."
    sudo ip netns exec $NS_NAME ip addr add $DHCP_IP dev $VETH_NS 2>/dev/null || echo "AVISO: IP $DHCP_IP ya asignada en namespace."
    sudo ip netns exec $NS_NAME ip link set dev $VETH_NS up
    sudo ip netns exec $NS_NAME ip link set dev lo up
    echo "OK: Interfaz '$VETH_NS' configurada en namespace con IP ${BASE}.2."

    # Verificar si dnsmasq ya corre en el namespace
    if sudo ip netns exec $NS_NAME pgrep dnsmasq > /dev/null; then
        echo "AVISO: dnsmasq ya está corriendo en '$NS_NAME', no se lanzará otro."
    else
        MASK=$(python3 -c "import ipaddress; print(str(ipaddress.IPv4Network('${CIDR}', strict=False).netmask))")
        sudo ip netns exec $NS_NAME dnsmasq \
            --interface=$VETH_NS \
            --dhcp-range=${DHCP_START},${DHCP_END},${MASK},12h \
            --dhcp-option=3,${GW_ADDR}
        echo "OK: dnsmasq iniciado en '$NS_NAME' con rango $DHCP_START - $DHCP_END, gateway $GW_ADDR."
    fi

elif [ "$DHCP" == "nodhcp" ]; then
    echo "OK: Red VLAN $VLAN_ID creada sin DHCP. Asigna IPs manualmente en el rango $NETWORK/$PREFIX, gateway $GW_ADDR."

else
    echo "ERROR: Tercer parámetro inválido '$DHCP'. Usa 'dhcp' o 'nodhcp'."
    exit 1
fi

echo "---------------------------------------"
echo "OK: Red VLAN $VLAN_ID desplegada exitosamente."
echo "    CIDR:    $CIDR"
echo "    Gateway: $GW_ADDR"
echo "    DHCP:    $DHCP"
echo "---------------------------------------"
