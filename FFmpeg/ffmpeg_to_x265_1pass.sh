#!/usr/bin/env bash

### set USAGE message
MESSAGE=$'USAGE: ffmpeg_to_x265 <resolution> <qp> \nExample: ffmpeg_to_x265 640:-1 18'

# check and set parameters
if [ -z "$1" ]; then
	echo "$MESSAGE"
	exit 1
fi
if [ -z "$2" ]; then
	echo "$MESSAGE"
	exit 1
fi

# libx265 entered parameters
echo Resolution: "$1"
RESOLUTION="$1"
echo QP: "$2"
QP="$2"
echo Passes: 1pass encoding

# convert every file in dir
for FILE in *{.mp4,h264,mkv,avi}
do
	[ -e "$FILE" ] || continue
	echo "##########"
	echo Converting "$FILE" to MKV container :: -c:v libx265 :: -codec:a aac
	echo "##########"

	# timeout confirmation
	echo "converting all files in" "$(pwd)"
	echo "10 seconds to cancel..."
	echo "-----------------------"
	sleep 10s

	#first pass
	echo "Y" | ffmpeg -i "$FILE" -vf scale="$RESOLUTION" -c:v libx265 -qp "$QP" -threads 8 -preset veryfast -c:a aac -b:a 128k "${FILE%.*}"_encode.mkv

	echo Conversion of "$FILE" successful!
done
