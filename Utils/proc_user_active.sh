#!/usr/bin/env bash

# Muestra los procesos iniciados por un usuario

echo "Procesos por usuario"
echo "************************"
ps aux | awk '{print $1}' | sort | uniq -c | sort
