#!/usr/bin/env bash

### set USAGE message
MESSAGE="USAGE: ffscreengrab <snd_server> <snd_rec_device> <framerate> <libx264|libx265> <crf_value> <preset> 
	Example: ffscreengrab sndio snd/0 30 libx264 23 veryfast
	Output: Video in MKV container using libx264 | crf 22 | veryfast | audio acc | sterero

	More info: https://ffmpeg.org/ffmpeg.html"

# Check and set parameters
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

if [ -z "$5" ]; then
	echo "$MESSAGE"
	exit 1
fi

if [ -z "$6" ]; then
	echo "$MESSAGE"
	exit 1
fi


# Initializating screen recording
echo "Initializating screen recording..."
echo "******************************************"

SND_SERVER="$1"
SND_REC_DEVICE="$2"
FRAMERATE="$3"
VIDEO_CODEC="$4"
CRF_VALUE="$5"
CODEC_PRESET="$6"

# Video folder
VIDEO_FOLDER="$( xdg-user-dir VIDEOS )"

# Random name for video
TODAY="$( date +"%Y-%m-%d" )"
NUMBER=0
COUNT=0

while [[ -f $VIDEO_FOLDER/record-$TODAY-$COUNT.mkv ]]
do
    (( ++NUMBER ))
    COUNT="$( printf -- '-%02d' "$NUMBER" )"
done

# Output for file
fname="$VIDEO_FOLDER/record-$TODAY-$COUNT.mkv"

# Show data for video recording and path for video 
echo "Init recording using..."
echo "Sound sever: $SND_SERVER"
echo "Mic Device: $SND_REC_DEVICE"
echo "Framerate: $FRAMERATE"
echo "Video Codec: $VIDEO_CODEC"
echo "Output: Video in MKV container using $VIDEO_CODEC | crf $CRF_VALUE | $CODEC_PRESET | audio acc | stereo"
echo "Video path: $fname"
echo "Record begin in 10 seconds...Cancel using CTRL+C"
echo ""

sleep 10

# Command for ffmpeg
ffmpeg -y \
    -thread_queue_size 512 \
    -f $SND_SERVER -i $SND_REC_DEVICE -ac 2 \
    -f x11grab -r $FRAMERATE \
    -s $(xdpyinfo | grep dimensions | awk '{print $2;}') \
    -i :0.0 -c:v $VIDEO_CODEC -crf $CRF_VALUE -preset $CODEC_PRESET -c:a aac \
    $fname

