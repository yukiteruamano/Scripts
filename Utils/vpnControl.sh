#!/usr/local/bin/bash

# Cambiar las opciones para adjustarlas a tus necesidades

# Activamos o desactivamos VPNs adicionales en el sistema
function vpn_control() {

    if [ "$1" == "enable" ]; then

	echo "Activando VPN 01"

	# Detenemos el VPN por default
        service openvpn stop

	sleep 5

	# Activamos el VPN 01
	openvpn --config /usr/local/etc/openvpn/vpn01.ovpn &
        sleep 5

	echo "VPN 01 Activado"

        exit 0

    elif [ "$1" == "disable" ]; then

	echo "Desactivando VPN 01"

	# Detenemos el VPN 01
        pkill openvpn
	sleep 5

	# Activamos el VPN por defecto
	service openvpn start
        sleep 5

	echo "VPN 01 Desactivado...VPN por defecto activo"

        exit 0

    else
        echo "Indique alguna opción. Opciones válidas: enable o disable"
        exit 0
    fi
}

# Comprobando permisos
# Primeros verificamos que el usuario tenga permisos de root
function is_root_user() {
    if [ "$USER" != "root" ]; then
        echo "Permiso denegado."
        echo "Este programa solo puede ser ejecutado por el usuario root"
        echo "Use sudo/doas para poder garantizar permisos administrativos"
        exit
    else
	# Iniciamos programa
	vpn_control $1
    fi
}

# Llamada a la función de inicialización
is_root_user $1
