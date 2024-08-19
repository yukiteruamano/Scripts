#!/usr/bin/env bash
# Author: Jose Maldonado
# License: BSD
#
# Dependencies: 7zip and zip packages
#

for FILE in *{.cbr,.CBR}
do
	[ -e "$FILE" ] || continue
	echo Converting $FILE to cbz format.
	DIR="${FILE%.*}"
	mkdir "$DIR";
	7z x -o{"$DIR"} ./"$FILE";
	zip -r "$DIR".cbz "$DIR";
	rm -r "$DIR";
	echo Conversion of $FILE successful!
done
