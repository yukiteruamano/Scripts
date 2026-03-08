#!/usr/bin/env bash

# User Process Activity Script
# Supports: Linux, FreeBSD, OpenBSD

OS=$(uname -s)

echo "--- User Process Activity ($OS) ---"
echo "********************************************"

case "$OS" in
    Linux)
        PROC_MAX=$(cat /proc/sys/kernel/threads-max 2>/dev/null || echo "N/A")
        echo "Active Processes per User:"
        ps -e -o user= | sort | uniq -c | sort -rn
        echo ""
        echo "Active Threads per User:"
        ps -eL -o user= | sort | uniq -c | sort -rn
        ;;
    FreeBSD)
        PROC_MAX=$(sysctl -n kern.maxproc 2>/dev/null || echo "N/A")
        echo "Active Processes per User:"
        ps -ax -o user= | sort | uniq -c | sort -rn
        echo ""
        echo "Active Threads per User (LWP):"
        ps -axH -o user= | sort | uniq -c | sort -rn
        ;;
    OpenBSD)
        PROC_MAX=$(sysctl -n kern.maxproc 2>/dev/null || echo "N/A")
        echo "Active Processes per User:"
        ps -ax -o user= | sort | uniq -c | sort -rn
        ;;
    *)
        echo "Error: Unsupported OS '$OS'"
        exit 1
        ;;
esac

echo ""
echo "System Max Processes: $PROC_MAX"
echo "User ($USER) Limit:   $(ulimit -u 2>/dev/null || echo "N/A")"
