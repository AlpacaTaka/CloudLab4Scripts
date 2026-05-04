#!/bin/bash
# Uso: bash createcontainer.sh <NOMBRE_CONT> <NOMBRE_OVS> <VLAN_ID>
# Ejemplo: ssh ubuntu@SERVER-1 bash -s < createcontainer.sh containervlan100 br-int 100

CONT_NAME=$1
OVS_NAME=$2
VLAN_ID=$3

# Validar parámetros
if [ -z "$CONT_NAME" ] || [ -z "$OVS_NAME" ] || [ -z "$VLAN_ID" ]; then
    echo "ERROR: Faltan parámetros. Uso: createcontainer.sh <NOMBRE_CONT> <OVS> <VLAN_ID>"
    exit 1
fi

# Verificar que el bridge existe
if ! sudo ovs-vsctl br-exists $OVS_NAME; then
    echo "ERROR: El bridge '$OVS_NAME' no existe. Ejecuta computeinit.sh primero."
    exit 1
fi

# Verificar que el contenedor no existe ya
if sudo docker ps -a --format '{{.Names}}' | grep -q "^${CONT_NAME}$"; then
    echo "ERROR: El contenedor '$CONT_NAME' ya existe."
    exit 1
fi

VETH_OVS="veth_ovs_${VLAN_ID}"
VETH_CONT="veth_cont_${VLAN_ID}"

# Verificar que el par veth no existe ya
if ip link show $VETH_OVS &>/dev/null; then
    echo "ERROR: La interfaz '$VETH_OVS' ya existe. ¿Ya hay un contenedor en VLAN $VLAN_ID?"
    exit 1
fi

# Crear contenedor sin red
sudo docker run --rm --network none --name $CONT_NAME \
    --cap-add NET_ADMIN -d alpine sleep infinity

if [ $? -ne 0 ]; then
    echo "ERROR: No se pudo crear el contenedor '$CONT_NAME'."
    exit 1
fi
echo "OK: Contenedor '$CONT_NAME' creado."

# Crear par veth
sudo ip link add $VETH_OVS type veth peer name $VETH_CONT
echo "OK: Par veth '$VETH_OVS' <-> '$VETH_CONT' creado."

# Agregar extremo OvS al bridge con tag VLAN
if ! sudo ovs-vsctl list-ports $OVS_NAME | grep -q "^${VETH_OVS}$"; then
    sudo ovs-vsctl add-port $OVS_NAME $VETH_OVS tag=${VLAN_ID}
    echo "OK: Puerto '$VETH_OVS' agregado a '$OVS_NAME' con tag VLAN $VLAN_ID."
fi
sudo ip link set dev $VETH_OVS up

# Mover extremo al namespace del contenedor
PID=$(sudo docker inspect -f '{{.State.Pid}}' $CONT_NAME)
sudo ip link set $VETH_CONT netns $PID
echo "OK: Interfaz '$VETH_CONT' movida al contenedor (PID $PID)."

# Levantar interfaz dentro del contenedor
sudo docker exec $CONT_NAME ip link set dev $VETH_CONT up
sudo docker exec $CONT_NAME ip link set dev lo up

echo "---------------------------------------"
echo "OK: Contenedor '$CONT_NAME' desplegado exitosamente."
echo "    OvS:  $OVS_NAME"
echo "    VLAN: $VLAN_ID"
echo "    veth: $VETH_OVS <-> $VETH_CONT"
echo "    Para DHCP dentro del contenedor:"
echo "    sudo docker exec $CONT_NAME udhcpc -i $VETH_CONT"
echo "---------------------------------------"