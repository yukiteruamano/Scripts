#!/usr/bin/env sh

# Obtain memory info for i3status usage

while :
do
    # Extract data from vmstat in megabytes
    USED_MEM=$( vmstat | tail -1 | awk '{ print $3 }' | sed 's/M//g' )

    # Physical memory
    PHY_MEM=$( sysctl hw.physmem | awk '{print $1}' | sed 's/hw.physmem=//g' )

    # Free memory in gigabytes
    USED_MEM_G=$(echo "scale=2; $USED_MEM / 1024" | bc -l)
    PHY_MEM_G=$(echo "scale=2; $PHY_MEM / (1024*1024*1024)" | bc -l)

    # Total memory in system
    SHOW_MEM="$USED_MEM_G G / $PHY_MEM_G G"

    echo "$SHOW_MEM"

    sleep 5

done
