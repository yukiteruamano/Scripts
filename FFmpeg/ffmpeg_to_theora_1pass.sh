#!/usr/bin/env bash

### set USAGE message
MESSAGE=$'USAGE: ffmpeg_to_webm <resolution> <minrate> <bitrate> <maxrate>\nExample: ffmpeg_to_webm 640:-1 500k 3000k 5500k'

# check and set parameters
if [ -z "$1" ]; then
	echo "$MESSAGE"
	exit 1
fi
if [ -z "$2" ]; then
	echo "$MESSAGE"
	exit 1
fi
if [ -z "$3" ]; then
	echo "$MESSAGE"
	exit 1
fi
if [ -z "$4" ]; then
	echo "$MESSAGE"
	exit 1
fi

# show entered parameters
echo Resolution: "$1"
RESOLUTION="$1"
echo Minrate: "$2"
MINRATE="$2"
echo Bitrate: "$3"
BITRATE="$3"
echo Maxrate: "$4"
MAXRATE="$4"
echo Passes: 1pass encoding

# convert every file in dir
for FILE in *{.mp4,h264,mkv,avi}
do
	[ -e "$FILE" ] || continue
	echo "##########"
	echo Converting "$FILE" to MKV container :: -c:v libtheora :: -codec:a libvorbis
	echo "##########"

	# timeout confirmation
	echo "converting all files in" "$(pwd)"
	echo "10 seconds to cancel..."
	echo "-----------------------"
	sleep 10s


	#first pass
	echo "Y" | ffmpeg -i "$FILE" -vf scale="$RESOLUTION" -c:v libtheora -minrate "$MINRATE" -b:v "$BITRATE" -maxrate "$MAXRATE" -threads 8 -c:a libvorbis -b:a 128k "${FILE%.*}"_encode.mkv
	
	echo Conversion of "$FILE" successful!
done
