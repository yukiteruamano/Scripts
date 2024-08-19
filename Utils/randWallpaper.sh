#/usr/bin/env sh

DISPLAY=:0 feh --bg-fill "$(find /home/yukiteru/DATA/PersonalSync/Wallpapers/* -type f | sort --random-sort | head -n 1)"
