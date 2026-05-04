#!/bin/bash
# Uso: bash headnodeinit.sh <iface1> [iface2] ...
# Ejemplo: ssh ubuntu@SERVER-3 bash -s < headnodeinit.sh ens4

INTERFACES="$@"

if [ -z "$INTERFACES" ]; then
    echo "ERROR: Debes indicar al menos una interfaz."
    exit 1
fi

if ! sudo ovs-vsctl br-exists br-int; then
    sudo ovs-vsctl add-br br-int
    echo "OK: Bridge br-int creado."
else
    echo "AVISO: Bridge br-int ya existe, se reutilizará."
fi

for IFACE in $INTERFACES; do
    # Verificar que no sea ens3
    if [ "$IFACE" == "ens3" ]; then
        echo "ERROR: No se permite agregar ens3 al bridge (red de acceso). Saltando..."
        continue
    fi

    # Verificar que la interfaz existe en el sistema
    if ! ip link show "$IFACE" &>/dev/null; then
        echo "ERROR: La interfaz '$IFACE' no existe en este servidor. Saltando..."
        continue
    fi

    # Agregar al OvS si no está ya
    if ! sudo ovs-vsctl list-ports br-int | grep -q "^${IFACE}$"; then
        sudo ovs-vsctl add-port br-int $IFACE
        echo "OK: Interfaz '$IFACE' agregada al bridge."
    else
        echo "AVISO: '$IFACE' ya está en el bridge, se omite."
    fi

    sudo ip link set dev $IFACE up
done

sudo sysctl -w net.ipv4.ip_forward=1
echo "OK: IPv4 Forwarding activado."

sudo iptables -P FORWARD DROP
echo "OK: Política FORWARD cambiada a DROP."