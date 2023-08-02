#!/usr/bin/env bash

# Record screen using ffmpeg and audio using aucat in OpenBSD

### set USAGE message
MESSAGE="USAGE: ffscreengrab <snd_rec_device> <framerate> <libx264|libx265> <crf_value> <preset>
	Example: ffscreengrab snd/0 30 libx264 23 veryfast Live
	Output: Video in MKV container using libx264 | crf 22 | veryfast | audio acc | stereo
	Output: Audio in WAV file (using aucat)"


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

# Initializating screen recording
echo "Initializating screen recording..."
echo "******************************************"

SND_REC_DEVICE="$1"
FRAMERATE="$2"
VIDEO_CODEC="$3"
CRF_VALUE="$4"
CODEC_PRESET="$5"

# Video and audio save Folder
VIDEO_FOLDER="$( xdg-user-dir VIDEOS )"

# Random name for video
TODAY="$( date +"%Y-%m-%d" )"
NUMBER=0
COUNT=0

while [[ -f $VIDEO_FOLDER/record-video-$TODAY-$COUNT.mkv ]]
do
    (( ++NUMBER ))
    COUNT="$( printf -- '-%02d' "$NUMBER" )"
done

# Output for file
vname="$VIDEO_FOLDER/record-video-$TODAY-$COUNT.mkv"
aname="$VIDEO_FOLDER/record-audio-$TODAY-$COUNT.wav"

# Show data for video recording and path for video 
echo "Init recording using..."
echo "Mic Device: $SND_REC_DEVICE"
echo "Framerate: $FRAMERATE"
echo "Video Codec: $VIDEO_CODEC"
echo "Output: Audio in WAV file using $SND_REC_DEVICE"
echo "Output: Video in MKV container using $VIDEO_CODEC | crf $CRF_VALUE | $CODEC_PRESET | audio acc | stereo"
echo "Video path: $vname"
echo "Audio path: $aname"
echo "Record begin in 10 seconds...Cancel or finish record using CTRL+C"
echo ""

sleep 10

# Command for ffmpeg and aucat

trap "kill 0 " INT

aucat -f "$SND_REC_DEVICE" -o "$aname" & \
ffmpeg -y \
    -thread_queue_size 512 \
    -f x11grab -r "$FRAMERATE" \
    -s "$(xdpyinfo | grep dimensions | awk '{print $2;}')" \
    -i :0.0 -c:v "$VIDEO_CODEC" -crf "$CRF_VALUE" -preset "$CODEC_PRESET" \
    "$vname"

kill 0
