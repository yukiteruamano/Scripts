#!/usr/bin/env bash

# Indica el número de archivos abiertos por cada proceso
echo "Archivos abiertos por cada proceso"
echo "********************************************"

fstat | awk '{print $2":pid "$3}' | sort | uniq -c | sort
