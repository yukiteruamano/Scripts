#!/usr/bin/env bash

# fail if any commands fails
set -e
# debug log
#set -x

DATE_START=$(date +%FT%H:%M)
DATE_END=$(date +%FT%H:%M --date="next minute")
XMR_PRICE=$(curl -s "https://production.api.coindesk.com/v2/price/values/XMR?start_date=${DATE_START}&end_date=${DATE_END}&ohlc=false" | jq '.data.entries[][1]')
printf "%0.0f\n" "${XMR_PRICE}"
