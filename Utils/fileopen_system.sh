#!/usr/bin/env bash

# File Descriptor and System Limits Monitoring Script
# Supports: Linux, FreeBSD, OpenBSD

OS=$(uname -s)

echo "--- File Descriptor Info ($OS) ---"
echo "********************************************"

case "$OS" in
Linux)
    # /proc/sys/fs/file-nr fields: 1=open, 2=unused, 3=max
    SYS_OPEN=$(awk '{print $1}' /proc/sys/fs/file-nr 2>/dev/null || echo "N/A")
    SYS_MAX=$(awk '{print $3}' /proc/sys/fs/file-nr 2>/dev/null || echo "N/A")
    # User open files count
    if command -v lsof >/dev/null; then
        USER_OPEN=$(lsof -u "$USER" -n -P 2>/dev/null | awk 'NR>1' | wc -l | tr -d ' ')
    else
        # Fallback estimation using /proc/PID/fd
        USER_OPEN=$(ls -d /proc/*/fd 2>/dev/null | grep -o "/proc/[0-9]*/fd" | while read -r fd_path; do
            pid=$(echo "$fd_path" | cut -d/ -f3)
            if [ "$(stat -c %u "$fd_path" 2>/dev/null)" = "$(id -u)" ]; then
                ls "$fd_path" 2>/dev/null | wc -l
            fi
        done | awk '{s+=$1} END {print s}')
        [ -z "$USER_OPEN" ] && USER_OPEN=0
    fi
    ;;
FreeBSD)
    SYS_OPEN=$(sysctl -n kern.openfiles 2>/dev/null || echo "N/A")
    SYS_MAX=$(sysctl -n kern.maxfiles 2>/dev/null || echo "N/A")
    USER_OPEN=$(fstat -u "$USER" 2>/dev/null | awk 'NR>1' | wc -l | tr -d ' ')
    ;;
OpenBSD)
    SYS_OPEN=$(sysctl -n kern.nfiles 2>/dev/null || echo "N/A")
    SYS_MAX=$(sysctl -n kern.maxfiles 2>/dev/null || echo "N/A")
    USER_OPEN=$(fstat -u "$USER" 2>/dev/null | awk 'NR>1' | wc -l | tr -d ' ')
    ;;
*)
    echo "Error: Unsupported OS '$OS'"
    exit 1
    ;;
esac

USER_LIMIT_SOFT=$(ulimit -Sn 2>/dev/null || echo "N/A")
USER_LIMIT_HARD=$(ulimit -Hn 2>/dev/null || echo "N/A")

echo "GLOBAL SYSTEM VALUES:"
echo "  Open Files (System-wide): $SYS_OPEN"
echo "  Max Files (System-wide):  $SYS_MAX"
echo ""
echo "USER VALUES ($USER):"
echo "  Open Files (Current):    $USER_OPEN"
echo "  Limit (Soft):            $USER_LIMIT_SOFT"
echo "  Limit (Hard):            $USER_LIMIT_HARD"
echo ""
echo "TOP 20 PROCESSES BY OPEN FILES:"
echo "Count  PID   Process"
echo "--------------------------------------------"

if [ "$OS" = "Linux" ]; then
    if command -v lsof >/dev/null; then
        # lsof -n (no DNS), -P (no port names)
        lsof -n -P 2>/dev/null | awk 'NR > 1 {print $2, $1}' | sort | uniq -c | sort -rn | head -n 20
    else
        # Fallback to /proc if lsof is missing
        find /proc -maxdepth 2 -name fd 2>/dev/null | while read -r f; do
            pid=$(echo "$f" | cut -d/ -f3)
            comm=$(cat "/proc/$pid/comm" 2>/dev/null || echo "unknown")
            count=$(ls "$f" 2>/dev/null | wc -l)
            echo "$count $pid $comm"
        done | sort -rn | head -n 20
    fi
else
    # BSDs (fstat is standard)
    # fstat output: USER CMD PID FD ...
    fstat 2>/dev/null | awk 'NR > 1 {print $3, $2}' | sort | uniq -c | sort -rn | head -n 20
fi
