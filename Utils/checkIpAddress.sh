#!/usr/bin/env sh

if [ "$1" == "public" ]; then
    ip=$(curl --silent --connect-timeout 1 ifconfig.me)
elif [ "$1" == "private" ]; then
    ip=$(ifconfig $2 | grep -i mask | awk '{print $2}')
fi
if [ -n "$ip" ]; then
    echo "$ip"
else
    echo "n/a"
fi
