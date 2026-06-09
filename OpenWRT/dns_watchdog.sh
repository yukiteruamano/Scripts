#!/bin/sh

ADGUARD_IP="192.168.10.2"

# Realizar una consulta DNS real a AdGuard (espera máxima de 2 segundos)
# Redirigimos la salida a /dev/null porque solo nos interesa el código de salida (exit code)
if nslookup -timeout=2 localhost "$ADGUARD_IP" >/dev/null 2>&1; then
    # AdGuard está VIVO y respondiendo consultas
    STATUS_ACTUAL=$(uci -q get firewall.@redirect[0].enabled)
    
    # Si la regla de AdGuard estaba desactivada (status 0 o vacío), restauramos el flujo principal
    if [ "$STATUS_ACTUAL" = "0" ] || [ -z "$STATUS_ACTUAL" ]; then
        logger -t dns_watchdog "AdGuard ($ADGUARD_IP) está respondiendo consultas de nuevo. Restaurando flujo principal."
        uci set firewall.@redirect[0].enabled='1'   # Activa Forzar-DNS-AdGuard
        uci set firewall.@redirect[1].enabled='0'   # Desactiva Forzar-DNS-Router-Backup
        uci commit firewall
        /etc/init.d/firewall restart
    fi
else
    # AdGuard está CAÍDO o no resuelve DNS
    STATUS_ACTUAL=$(uci -q get firewall.@redirect[0].enabled)
    
    # Si la regla de AdGuard seguía activa, realizamos el failover al router
    if [ "$STATUS_ACTUAL" = "1" ]; then
        logger -t dns_watchdog "ALERTA: AdGuard ($ADGUARD_IP) falló la prueba nslookup. Activando contingencia hacia el Router."
        uci set firewall.@redirect[0].enabled='0'   # Desactiva Forzar-DNS-AdGuard
        uci set firewall.@redirect[1].enabled='1'   # Activa Forzar-DNS-Router-Backup
        uci commit firewall
        /etc/init.d/firewall restart
    fi
fi
