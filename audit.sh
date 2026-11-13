#!/usr/bin/env bash
#
# audit_perms.sh - Auditoría básica de permisos para Slackware (FHS-aligned)
#

# Asegurar que se ejecuta como root para acceder a todas las rutas
if [ "$EUID" -ne 0 ]; then
  echo "[-] Por favor, ejecuta este script como root (su o sudo)."
  exit 1
fi

echo "================================================================="
echo " Iniciando auditoría de permisos (Inspirado en Debian/FHS) "
echo "================================================================="

# 1. Archivos con escritura universal (World-Writable)
# Excluimos enlaces simbólicos, /proc, /sys y /dev que manejan permisos dinámicos.
echo -e "\n[*] Buscando archivos con escritura universal (excluyendo /proc, /sys, /dev)..."
find / \( -path /proc -o -path /sys -o -path /dev \) -prune -o -type f -perm -0002 -print 2>/dev/null

# 2. Directorios con escritura universal sin el bit Sticky (o+w sin +t)
# En el FHS, directorios como /tmp o /var/tmp deben tener el bit sticky (1777)
# para que los usuarios no puedan borrar archivos de otros.
echo -e "\n[*] Buscando directorios con escritura universal sin Sticky Bit..."
find / \( -path /proc -o -path /sys -o -path /dev \) -prune -o -type d -perm -0002 ! -perm -1000 -print 2>/dev/null

# 3. Binarios SUID y SGID en rutas críticas del sistema
# Slackware incluye varios binarios SUID por compatibilidad. Aquí listamos los que tienen
# permisos de ejecución universal para auditoría visual.
echo -e "\n[*] Listando archivos con bit SUID/SGID activo en /bin, /sbin, /usr/bin, /usr/sbin..."
find /bin /sbin /usr/bin /usr/sbin -type f \( -perm -4000 -o -perm -2000 \) -exec ls -ld {} + 2>/dev/null

# 4. Verificación de directorios de configuración global del FHS
# En un entorno seguro tipo Debian, /etc y subdirectorios críticos no deben ser legibles/escribibles por cualquiera.
echo -e "\n[*] Verificando permisos en rutas críticas de configuración..."
CRITICOS=(
  "/etc/shadow"
  "/etc/passwd"
  "/etc/gshadow"
  "/etc/group"
  "/etc/ssh"
)

for ruta in "${CRITICOS[@]}"; do
  if [ -e "$ruta" ]; then
    ls -ld "$ruta"
  else
    echo "[-] No se encontró: $ruta"
  fi
done

echo -e "\n================================================================="
echo " Auditoría finalizada. Revisa los hallazgos con cautela. "
echo "================================================================="
