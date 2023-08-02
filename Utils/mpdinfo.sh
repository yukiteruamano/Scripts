#!/usr/local/bin/bash

while :
do
    read line

    printf -v mpd_song "%q" "$(mpc current -f "[[%albumartist%|%artist% - ] - %title%]")"

    # printf -v sets the variable to '' in case of empty assignment
    if [[ "$mpd_song" == "''" ]]; then
        printf -v mpd_song "%q" "$(basename "$(mpc current -f "%artist% - %title%")")"
    fi

    status="$(mpc status)"
    mpd_status="$(echo "$status" | tail -2 | head -1 | cut -d' ' -f1 | tr -d '[]')"
    flag=1

    case "$mpd_status" in
        "playing" )
            color="#cba6f7" ;;
        "paused" )
            color="#cba6f7" ;;
        * )
            flag=0 ;;
    esac
    if (( flag == 1 )); then
        echo " $line" | sed 's|{\"name|{\"name\":\"music\",\"color\": \"'"$color"'\",\"full_text\":\"MPD: '"$mpd_song"'\"},{\"name|' || exit 1
        continue
    else
        echo -n "$line" || exit 1
        continue
    fi
done
