#!/usr/bin/env bash

# fail if any commands fails
set -e
# debug log
#set -x

BTC_PRICE=$(curl -s http://api.coindesk.com/v1/bpi/currentprice.json  | jq '.bpi.USD.rate' | tr -d '"' | sed 's:\.[^|]*::g' | sed 's/,//g')
printf "%0.0f\n" "${BTC_PRICE}"