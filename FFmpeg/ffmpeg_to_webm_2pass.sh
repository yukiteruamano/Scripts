#!/usr/bin/env bash

### set USAGE message
MESSAGE=$'USAGE: ffmpeg_to_webm <resolution> <constant rate factor (crf)>\nExample: ffmpeg_to_webm 640:-1 31'

# check and set parameters
if [ -z "$1" ]; then
	echo "$MESSAGE"
	exit 1
fi
if [ -z "$2" ]; then
	echo "$MESSAGE"
	exit 1
fi

# show entered parameters
echo Resolution: "$1"
RESOLUTION="$1"
echo Constant Rate Factor: "$2"
CRF="$2"
echo Passes: 2pass encoding

# timeout confirmation
echo converting all files in "$(pwd)"
echo 10 seconds to cancel...
echo -----------------------
sleep 10s

# convert every file in dir
for FILE in *{.mp4,h264,mkv,avi}
do
	[ -e "$FILE" ] || continue
	echo "##########"
	echo Converting "$FILE" to WEBM container :: -c:v libvpx-vp9 :: -c:a libopus
	echo "##########"
	
	#first pass
	echo "Y" | ffmpeg -i "$FILE" -vf scale="$RESOLUTION" -c:v libvpx-vp9 -pass 1 -b:v 0 -crf "$CRF" -threads 8 -speed 4 -tile-columns 6 -frame-parallel 1 -an -f webm /dev/null
	#second pass
	echo "Y" | ffmpeg -i "$FILE" -vf scale="$RESOLUTION" -c:v libvpx-vp9 -pass 2 -b:v 0 -crf "$CRF" -threads 8 -speed 2 -tile-columns 6 -frame-parallel 1 -auto-alt-ref 1 -lag-in-frames 25 -c:a libopus -b:a 128k -f webm "${FILE%.*}".webm
	
	echo Conversion of "$FILE" successful!
done
