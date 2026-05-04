#!/bin/bash
# Uso: bash createvm.sh <NOMBRE_VM> <NOMBRE_OVS> <VLAN_ID> <PUERTO_VNC>
# Ejemplo: ssh ubuntu@SERVER-1 bash -s < createvm.sh vmvlan100 br-int 100 1
# Puerto VNC 1 = display :1 = puerto 5901, Puerto VNC 2 = display :2 = puerto 5902

VM_NAME=$1
OVS_NAME=$2
VLAN_ID=$3
VNC_PORT=$4

# Validar parámetros
if [ -z "$VM_NAME" ] || [ -z "$OVS_NAME" ] || [ -z "$VLAN_ID" ] || [ -z "$VNC_PORT" ]; then
    echo "ERROR: Faltan parámetros. Uso: createvm.sh <NOMBRE_VM> <OVS> <VLAN_ID> <VNC_PORT>"
    exit 1
fi

# Verificar que br-int existe
if ! sudo ovs-vsctl br-exists $OVS_NAME; then
    echo "ERROR: El bridge '$OVS_NAME' no existe. Ejecuta computeinit.sh primero."
    exit 1
fi

MAC="52:54:00:$(printf '%02x' $VLAN_ID):$(printf '%02x' $VNC_PORT):01"
BASE_IMG="cirros-0.5.1-x86_64-disk.img"
VM_IMG="${VM_NAME}.qcow2"
TAP_NAME="${VM_NAME}tap"

# Verificar si la VM ya está corriendo
if pgrep -f "$VM_IMG" > /dev/null; then
    echo "ERROR: La VM '$VM_NAME' ya está corriendo."
    exit 1
fi

# Verificar si el disco delta ya existe
if [ -f "$VM_IMG" ]; then
    echo "ERROR: El disco '$VM_IMG' ya existe. Elimínalo primero con deletevm.sh."
    exit 1
fi

# Descargar imagen base si no existe
if [ ! -f "$BASE_IMG" ]; then
    echo "Imagen base no encontrada, descargando..."
    wget http://download.cirros-cloud.net/0.5.1/cirros-0.5.1-x86_64-disk.img
    if [ $? -ne 0 ]; then
        echo "ERROR: No se pudo descargar la imagen base."
        exit 1
    fi
    echo "OK: Imagen base descargada."
else
    echo "AVISO: Imagen base '$BASE_IMG' ya existe, se reutilizará."
fi

# Crear disco delta
qemu-img create -f qcow2 -b $BASE_IMG -F qcow2 $VM_IMG
echo "OK: Disco delta '$VM_IMG' creado."

# Crear TAP si no existe
if ! ip link show $TAP_NAME &>/dev/null; then
    sudo ip tuntap add mode tap name $TAP_NAME
    echo "OK: Interfaz TAP '$TAP_NAME' creada."
else
    echo "AVISO: El TAP '$TAP_NAME' ya existe, se reutilizará."
fi

# Levantar VM
sudo qemu-system-x86_64 -enable-kvm \
    -vnc 0.0.0.0:${VNC_PORT} \
    -netdev tap,id=tap1,ifname=${TAP_NAME},script=no,downscript=no \
    -device e1000,netdev=tap1,mac=${MAC} \
    -daemonize $VM_IMG

if [ $? -ne 0 ]; then
    echo "ERROR: No se pudo iniciar la VM '$VM_NAME'."
    exit 1
fi
echo "OK: VM '$VM_NAME' iniciada."

# Agregar TAP al OvS si no está ya
if ! sudo ovs-vsctl list-ports $OVS_NAME | grep -q "^${TAP_NAME}$"; then
    sudo ovs-vsctl add-port $OVS_NAME $TAP_NAME tag=${VLAN_ID}
    echo "OK: Puerto '$TAP_NAME' agregado a '$OVS_NAME' con tag VLAN $VLAN_ID."
else
    echo "AVISO: El puerto '$TAP_NAME' ya existe en '$OVS_NAME'."
fi

sudo ip link set dev $TAP_NAME up

echo "---------------------------------------"
echo "OK: VM '$VM_NAME' desplegada exitosamente."
echo "    OvS:     $OVS_NAME"
echo "    VLAN:    $VLAN_ID"
echo "    MAC:     $MAC"
echo "    VNC:     0.0.0.0:${VNC_PORT} (puerto 59$(printf '%02d' $VNC_PORT))"
echo "    Disco:   $VM_IMG"
echo "---------------------------------------"