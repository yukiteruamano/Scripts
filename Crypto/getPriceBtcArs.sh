#!/usr/bin/env bash

# fail if any commands fails
set -e
# debug log
#set -x

BTC_PRICE=$(curl -s "http://api.coindesk.com/v1/bpi/currentprice.json"  | jq '.bpi.USD.rate' | tr -d '"' | sed 's:\.[^|]*::g' | sed 's/,//g')
#USD_PRICE=$(curl -s "https://mercados.ambito.com//dolar/dolarturista/variacion" | jq '.venta' | tr -d '"' | sed 's:\,[^|]*::g')
USD_PRICE=$(curl -s "https://mercados.ambito.com//dolarturista/variacion" | jq '.venta' | tr -d '"' | sed 's:\,[^|]*::g')
BTS_PRICE_ARS=$(echo "${BTC_PRICE}*${USD_PRICE}" | bc)
#printf "%'d\n" ${RESULT}
printf "%0.0f\n" "${BTS_PRICE_ARS}"