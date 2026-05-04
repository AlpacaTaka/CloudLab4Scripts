#!/bin/bash
# Uso: bash deletevm.sh <NOMBRE_VM> <NOMBRE_OVS> <VLAN_ID> <PUERTO_VNC>
# Ejemplo: ssh ubuntu@SERVER-1 bash -s < deletevm.sh vmvlan100 br-int 100 1

VM_NAME=$1
OVS_NAME=$2
VLAN_ID=$3
VNC_PORT=$4

# Validar parámetros
if [ -z "$VM_NAME" ] || [ -z "$OVS_NAME" ] || [ -z "$VLAN_ID" ] || [ -z "$VNC_PORT" ]; then
    echo "ERROR: Faltan parámetros. Uso: deletevm.sh <NOMBRE_VM> <OVS> <VLAN_ID> <VNC_PORT>"
    exit 1
fi

TAP_NAME="${VM_NAME}tap"
VM_IMG="${VM_NAME}.qcow2"
BASE_IMG="cirros-0.5.1-x86_64-disk.img"

# Verificar que el bridge existe
if ! sudo ovs-vsctl br-exists $OVS_NAME; then
    echo "ERROR: El bridge '$OVS_NAME' no existe."
    exit 1
fi

# Detener VM si está corriendo
VM_PID=$(pgrep -f "$VM_IMG")
if [ -n "$VM_PID" ]; then
    sudo kill $VM_PID
    echo "OK: VM '$VM_NAME' detenida (PID $VM_PID)."
else
    echo "AVISO: La VM '$VM_NAME' no estaba corriendo."
fi

# Eliminar puerto OvS si existe
if sudo ovs-vsctl list-ports $OVS_NAME | grep -q "^${TAP_NAME}$"; then
    sudo ovs-vsctl del-port $OVS_NAME $TAP_NAME
    echo "OK: Puerto '$TAP_NAME' eliminado de '$OVS_NAME'."
else
    echo "AVISO: Puerto '$TAP_NAME' no encontrado en '$OVS_NAME'."
fi

# Eliminar TAP si existe
if ip link show $TAP_NAME &>/dev/null; then
    sudo ip link del $TAP_NAME
    echo "OK: Interfaz TAP '$TAP_NAME' eliminada."
else
    echo "AVISO: TAP '$TAP_NAME' no encontrado."
fi

# Eliminar disco delta si existe
if [ -f "$VM_IMG" ]; then
    rm -f $VM_IMG
    echo "OK: Disco '$VM_IMG' eliminado."
else
    echo "AVISO: Disco '$VM_IMG' no encontrado."
fi

# Eliminar imagen base si ya no tiene deltas
if [ -f "$BASE_IMG" ]; then
    DELTA_COUNT=$(find . -name "*.qcow2" 2>/dev/null | wc -l)
    if [ "$DELTA_COUNT" -eq 0 ]; then
        rm -f $BASE_IMG
        echo "OK: Imagen base '$BASE_IMG' eliminada (sin más discos delta)."
    else
        echo "AVISO: Imagen base conservada ($DELTA_COUNT disco(s) delta aún la usan)."
    fi
else
    echo "AVISO: Imagen base '$BASE_IMG' no encontrada."
fi

echo "---------------------------------------"
echo "OK: VM '$VM_NAME' eliminada exitosamente."
echo "    TAP:   $TAP_NAME"
echo "    Disco: $VM_IMG"
echo "    VLAN:  $VLAN_ID"
echo "---------------------------------------"