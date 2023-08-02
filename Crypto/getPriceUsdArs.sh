#!/usr/bin/env bash

# fail if any commands fails
set -e
# debug log
#set -x

USD_PRICE=$(curl -s "https://mercados.ambito.com//dolar/informal/variacion" | jq '.venta' | tr -d '"' | sed 's:\,[^|]*::g')
#curl -s "https://mercados.ambito.com//dolarturista/variacion" | jq '.venta' | tr -d '"' | sed 's:\,[^|]*::g'
printf "%0.0f\n" "${USD_PRICE}"