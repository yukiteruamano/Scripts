#!/bin/sh
# Bash script that generates film strip video preview using ffmpeg
# You can see live demo: http://jsfiddle.net/r6wz0nz6/2/
# Tutorial on Binpress.com: http://www.binpress.com/tutorial/generating-nice-video-previews-with-ffmpeg/138

get_date (){
	echo "$(date '+%Y%m%d-%H%M')"
}

show_usage (){
    printf "Usage: $0 [options [parameters]]\n"
    printf "  For all files in directory use like this:\n"
    printf "  $ for file in *{.mp4,h264,mkv,avi,rm,ts}; do $0 -f \"\$file\"; done\n"
    printf "  $ for file in *{.mp4,h264,mkv,avi,rm,ts}; do $0 -f \"\$file\" -h 120 -c 2 -r 4; done\n"
    printf "\n"
    printf "Mandatory options:\n"
    printf " -f|--file          [FILENAME.EXT]\n"
    printf "\n"
    printf "Options:\n"
    printf " -h|--height        [HEIGHT] (Optional, default: '120')\n"
    printf " -c|--cols          [COLS] (Optional, default: '2')\n"
    printf " -r|--rows          [ROWS] (Optional, default: '4')\n"
    printf " -h|--help, Print help\n"

exit
}

if [ "$1" = "--help" ] || [ "$1" = "-h" ];then
    show_usage
fi
if [ -z "$1" ]; then
    show_usage
fi

while [ -n "$1" ]; do
  case "$1" in
    --file|-f)
        shift
        echo "INFO: $(get_date) - $0 - Parameter file: $1"
        FILENAME=$1
        ;;
    --height|-h)
        shift
        echo "INFO: $(get_date) - $0 - Parameter height: $1"
        HEIGHT=$1
        ;;
    --cols|-c)
        shift
        echo "INFO: $(get_date) - $0 - Parameter cols: $1"
        COLS=$1
        ;;
    --rows|-r)
        shift
        echo "INFO: $(get_date) - $0 - Parameter rows: $1"
        ROWS=$1
        ;;
    *)
    show_usage
    ;;
  esac
shift
done

### Configuration
if [ -z "$HEIGHT" ]; then
	HEIGHT=120
fi
if [ -z "$COLS" ]; then
	COLS=2
fi
if [ -z "$ROWS" ]; then
	ROWS=4
fi
if [ -z "$FILENAME" ]; then
	show_usage
fi

# get video name without the path and extension
VIDEO_NAME=$(basename $FILENAME)
OUT_FILENAME=$(echo ${VIDEO_NAME%.*}_preview.jpg)
TOTAL_IMAGES=$(echo "$COLS*$ROWS" | bc)

if [ -e "$OUT_FILENAME" ]; then
	echo "INFO: $(get_date) - $0 - Preview found for $VIDEO_NAME. Skipping $OUT_FILENAME preview generation."
	exit 1
else
    echo "INFO: $(get_date) - $0 - Preview not found for $VIDEO_NAME. Generating $OUT_FILENAME preview..."
fi

# get total number of frames in the video
# ffprobe is fast but not 100% reliable. It might not detect number of frames correctly!
#NB_FRAMES=`ffprobe -show_streams "$VIDEO" 2> /dev/null | grep nb_frames | head -n1 | sed 's/.*=//'`
# `-show-streams` Show all streams found in the video. Each video has usualy two streams (video and audio).
# `head -n1` We care only about the video stream which comes first.
# `sed 's/.*=//'` Grab everything after `=`.

#if [ "$NB_FRAMES" = "N/A" ]; then
	# as a fallback we'll use ffmpeg. This command basically copies this video to /dev/null and it counts
    # frames in the process. It's slower (few seconds usually) than ffprobe but works everytime.
    NB_FRAMES=$(ffmpeg -nostats -i "$FILENAME" -vcodec copy -f rawvideo -y /dev/null 2>&1 | grep frame | awk '{split($0,a,"fps")}END{print a[1]}' | sed 's/.*= *//')
    # I know, that `awk` and `sed` parts look crazy but it has to be like this because ffmpeg can
    # `-nostats` By default, `ffmpeg` prints progress information but that would be immediately caught by `grep`
    #     because it would contain word `frame` and therefore output of this entire command would be totally
    #      random. `-nostats` forces `ffmpeg` to print just the final result.
    # `-i "$VIDEO"` Input file
    # `-vcodec copy -f rawvideo` We don't want to do any reformating. Force `ffmpeg` to read and write the video as is.
    # `-y /dev/null` Dump read video data. We just want it to count frames we don't care about the data.
    # `awk ...` The line we're interested in has format might look like `frame= 42` or `frame=325`. Because of that
    #     extra space we can't just use `awk` to print the first column and we have to cut everything from the
    #     beggining of the line to the term `fps` (eg. `frame= 152`).
    # `sed ...` Grab everything after `=` and ignore any spaces
#fi

# calculate offset between two screenshots, drop the floating point part
NTH_FRAME=$(echo "$NB_FRAMES/$TOTAL_IMAGES" | bc)
echo "INFO: $(get_date) - $0 - Capture every ${NTH_FRAME}th frame out of $NB_FRAMES frames"

# make sure output dir exists
#mkdir -p $OUT_DIR

FFMPEG_CMD="ffmpeg -loglevel panic -i \"$FILENAME\" -y -frames 1 -q:v 1 -vf \"select=not(mod(n\,$NTH_FRAME)),scale=-1:${HEIGHT},tile=${COLS}x${ROWS}\" \"$OUT_FILENAME\""
# `-loglevel panic` We don’t want to see any output. You can remove this option if you’re having any problem to see what went wrong
# `-i "$VIDEO"` Input file
# `-y` Override any existing output file
# `-frames 1` Tell `ffmpeg` that output from this command is just a single image (one frame).
# `-q:v 3` Output quality where `0` is the best.
# `-vf \"select=` That's where all the magic happens. Selector function for [video filter](https://trac.ffmpeg.org/wiki/FilteringGuide).
# # `not(mod(n\,58))` Select one frame every `58` frames [see the documentation](https://www.ffmpeg.org/ffmpeg-filters.html#Examples-34).
# # `scale=-1:120` Resize to fit `120px` height, width is adjusted automatically to keep correct aspect ration.
# # `tile=${COLS}x${ROWS}` Layout captured frames into this grid

# print enire command for debugging purposes
#echo $FFMPEG_CMD

eval "$FFMPEG_CMD"

echo "INFO: $(get_date) - $0 - Generated $OUT_FILENAME preview successfully."
