#!/bin/bash
# Uso: bash deletecontainer.sh <NOMBRE_CONT> <NOMBRE_OVS> <VLAN_ID>
# Ejemplo: ssh ubuntu@SERVER-1 bash -s < deletecontainer.sh containervlan100 br-int 100

CONT_NAME=$1
OVS_NAME=$2
VLAN_ID=$3

# Validar parámetros
if [ -z "$CONT_NAME" ] || [ -z "$OVS_NAME" ] || [ -z "$VLAN_ID" ]; then
    echo "ERROR: Faltan parámetros. Uso: deletecontainer.sh <NOMBRE_CONT> <OVS> <VLAN_ID>"
    exit 1
fi

VETH_OVS="veth_ovs_${VLAN_ID}"
VETH_CONT="veth_cont_${VLAN_ID}"

# Verificar que el contenedor existe
if ! sudo docker ps -a --format '{{.Names}}' | grep -q "^${CONT_NAME}$"; then
    echo "AVISO: El contenedor '$CONT_NAME' no existe."
else
    # Detener y eliminar contenedor
    sudo docker stop $CONT_NAME
    # Si no usó --rm al crearlo, eliminarlo manualmente
    sudo docker rm $CONT_NAME 2>/dev/null || true
    echo "OK: Contenedor '$CONT_NAME' detenido y eliminado."
fi

# Eliminar puerto OvS si existe
if sudo ovs-vsctl br-exists $OVS_NAME; then
    if sudo ovs-vsctl list-ports $OVS_NAME | grep -q "^${VETH_OVS}$"; then
        sudo ovs-vsctl del-port $OVS_NAME $VETH_OVS
        echo "OK: Puerto '$VETH_OVS' eliminado de '$OVS_NAME'."
    else
        echo "AVISO: Puerto '$VETH_OVS' no encontrado en '$OVS_NAME'."
    fi
else
    echo "AVISO: Bridge '$OVS_NAME' no existe, se omite limpieza de puertos."
fi

# Eliminar interfaz veth si aún existe (el extremo del contenedor
# desaparece solo al eliminar el contenedor)
if ip link show $VETH_OVS &>/dev/null; then
    sudo ip link del $VETH_OVS
    echo "OK: Interfaz '$VETH_OVS' eliminada."
else
    echo "AVISO: Interfaz '$VETH_OVS' ya no existe."
fi

echo "---------------------------------------"
echo "OK: Contenedor '$CONT_NAME' eliminado exitosamente."
echo "    VLAN: $VLAN_ID"
echo "    veth: $VETH_OVS eliminado"
echo "---------------------------------------"