#!/usr/bin/env sh

nc -z -w 5 8.8.8.8 53  >/dev/null 2>&1
online=$?

if [ $online -eq 0 ]; then
    echo "ok"
else
    echo "off"
fi
