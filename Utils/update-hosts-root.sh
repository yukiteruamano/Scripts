#!/bin/bash

# Filename: update-hosts.sh
#
# Author: George Lesica <george@lesica.com>
# Enhanced by Eliastik ( eliastiksofts.com/contact )
# Version 1.3 (22 april 2021) - Eliastik
#
# Description: Replaces the HOSTS file with hosts lists from Internet,
# creating a backup of the old file. Can be used as an update script.
#
# Enhancement by Eliastik :
# Added the possibility to download multiple hosts files from multiple sources,
# added the possibility to use an initial hosts file to be appended at the top
# of the system hosts file, added a possibility to uninstall and restore
# the hosts file, added incorrect/malicious entries checking,
# added the possibility to exclude hosts filtering for specific domains, others fixes.
#
# Can be used as a cron script.
#
# Launch arguments:
# - Without arguments (./update-hosts.sh), the script update the hosts file
# - With restore (./update-hosts.sh restore), the script restore the backup hosts file if it exists
# - With uninstall (./update-hosts.sh uninstall), the script uninstall the hosts file and restore only the initial hosts file
# - With check (./update-hosts.sh check), the script check the hosts file for incorrect or malicious entries (no root needed)

# Configuration variables:
# Add an hosts source by adding a space after the last entry of the variable HOSTS_URLS (before the ")"), then by adding your URL with quotes (ex: "http://www.example.com/hosts.txt")
HOSTS_URLS=( "https://someonewhocares.org/hosts/zero/hosts" "https://pgl.yoyo.org/adservers/serverlist.php?showintro=0&mimetype=plaintext&useip=0.0.0.0" "https://winhelp2002.mvps.org/hosts.txt" )
HOSTS_PATH="/etc/hosts" # The path to the hosts file
INITIAL_HOSTS="/etc/hosts.initial" # The initial host file to be appended at the top of the hosts file
EXCLUDE_HOSTS="/etc/hosts.exclude" # A file containing a list of domain to be excluded from the hosts file (1 domain per line)
NEW_HOSTS="hosts" # New host name
NB_MAX_DOWNLOAD_RETRY=10
CHECK_HOSTS=0 # 1 for checking for malicious entries, 0 to disable
GOOD_HOSTS=( "127."*"."*"."* "10."*"."*"."* "0.0.0.0" "255.255.255.255" "::1" "fe"*"::"* "ff0"*"::"* ) # A list of safe hosts

function check_hosts() {
    echo "Checking hosts data..."
    lineNumber=0
    fileLines=$(cat $HOSTS_PATH | tr '\t' ' ' | tr '\r' ' ' | sed -e 's/^[[:space:]]*//' | cut -d " " -f1)

    while IFS= read -r line; do
            lineNumber=$((lineNumber + 1))
            found=0
            first_word="$(echo "$line" | head -n1)"
            first_letter="$(echo "$first_word" | head -c 1)"

            if [ -n "${first_word// }" ] && [ "$first_letter" != "#" ]; then
                for i in "${GOOD_HOSTS[@]}"; do
                    if [[ "$first_word" == $i ]]; then
                        found=1
                    fi
                done

                if [ "$found" = "0" ]; then
                    echo "Found incorrect or malicious entry. Exiting..."
                    echo "Entry found: '${line}' at line $lineNumber"
                    return 1
                fi
            fi
    done <<< "$fileLines"
    
    echo "No incorrect or malicious entry found."
    return 0
}

function check_root() {
    if [ "$(id -u)" -ne "0" ]; then
        echo "This script must be run as root. Exiting..." 1>&2
        exit 1
    fi
}

function check_curl() {
    if ! [ -x "$(command -v curl)" ]; then
        echo "Error: curl is not installed. Please install it to run this script." >&2
        exit 1
    fi
}

# Check for arguments - restore or uninstall the hosts file
if [ $# -ge 1 ]; then
    if [ "$1" = "restore" ]; then
        check_root
        echo "Restoring your hosts file backup..."
        if [ -f "${HOSTS_PATH}.bak" ]; then
            cp -v ${HOSTS_PATH}.bak $HOSTS_PATH
            echo "Done!"
            exit 0
        else
            echo "The backup hosts file doesn't exist: ${HOSTS_PATH}.bak"
            echo "Exiting..."
            exit 1
        fi
    fi

    if [ "$1" = "uninstall" ]; then
        check_root
        echo "Uninstalling your hosts file and restoring initial hosts file..."
        if [ -f "$INITIAL_HOSTS" ]; then
            cp -v $INITIAL_HOSTS $HOSTS_PATH
            echo "Done!"
            exit 0
        else
            echo "The initial hosts file doesn't exist: $INITIAL_HOSTS"
            echo "Exiting..."
            exit 1
        fi
    fi

    if [ "$1" = "check" ]; then
        if [ -f "${HOSTS_PATH}" ]; then
            check_hosts $HOSTS_PATH || exit 1
            exit 0
        else
            echo "The hosts file doesn't exist: $HOSTS_PATH"
            echo "Exiting..."
            exit 1
        fi
    fi
fi

check_root # Check for root
check_curl # Check for curl

# Check for hosts file
if [ ! -f "${HOSTS_PATH}" ]; then
    echo "The hosts file doesn't exist: $HOSTS_PATH"
    echo "Exiting..."
    exit 1
fi

# Create temporary directory
echo "Creating temporary directory..."
TEMP_DIR=`mktemp -d`

if [[ ! "$TEMP_DIR" || ! -d "$TEMP_DIR" ]]; then
    echo "The temporary directory could not have been created. Exiting securely..."
    exit 1
fi

cd "$TEMP_DIR"
echo "Created temporary directory at $(pwd)"

# Create new temp hosts
echo "">$NEW_HOSTS

# Print the update time
DATE=`date '+%Y-%m-%d %H:%M:%S'`
echo "">>$NEW_HOSTS
echo "# HOSTS last updated: $DATE">>$NEW_HOSTS
echo "#">>$NEW_HOSTS

# Grab hosts file
for i in "${HOSTS_URLS[@]}"
do
   :
        nberror=0
        echo "Downloading hosts list from: $i"

        while true; do
            curl -s --fail "$i">>$NEW_HOSTS && break ||
            nberror=$((nberror + 1))
            echo "Download failed ! Retrying..."

            if [ $nberror -ge $NB_MAX_DOWNLOAD_RETRY ]; then
                echo "Download failed $NB_MAX_DOWNLOAD_RETRY time(s). Check your Internet connection and the hosts source then try again. Exiting..."
                exit 1
            fi
        done
done

# Backup old hosts file
echo "Backup old hosts file..."
cp -v $HOSTS_PATH ${HOSTS_PATH}.bak

if ! [ -f "${HOSTS_PATH}.bak" ]; then
    echo "HOSTS file backup not created. Exiting securely..."
    exit 1
fi

# Exclude hosts (from EXCLUDE_HOSTS file)
if [ -f "$EXCLUDE_HOSTS" ]; then
    echo "Excluding hosts..."
    lineNumber=0
    linesHost=$(cat "$NEW_HOSTS" | tr '\t' ' ' | tr '\r' ' ')
    linesHostExcluded=$(cat "$EXCLUDE_HOSTS" | tr '\t' ' ' | tr '\r' ' ')
            
    while read -r lineHost; do
        lineNumber=$((lineNumber + 1))
        excludedHost=0
        fileHost=$(echo "$lineHost" | tr '\t' ' ' | tr '\r' ' ' | sed -e 's/^[[:space:]]*//' | cut -d " " -f2 | head -n2)
        
        while read -r lineExclude; do
            if [[ "$fileHost" == $lineExclude ]]; then
                echo "Excluded '${lineHost}' (line $lineNumber)"
                excludedHost=1
            fi
        done <<< $linesHostExcluded
        
        if [ "$excludedHost" = "0" ]; then
            echo "$lineHost">>$NEW_HOSTS".tmp"
        fi
    done <<< $linesHost
    
    echo "">$NEW_HOSTS
    cat $NEW_HOSTS".tmp">>$NEW_HOSTS
fi

# Checking new hosts
if [ "$CHECK_HOSTS" = "1" ]; then
    check_hosts $NEW_HOSTS || ( echo "You can disable hosts checking by changing the value of the variable CHECK_HOSTS to 0 in the script." && exit 1 )
fi

# Install hosts
echo "Installing hosts list..."

# Copy initial hosts
if [ -f "$INITIAL_HOSTS" ]; then
    cat $INITIAL_HOSTS>$HOSTS_PATH
else
    echo "The initial hosts file doesn't exist: $INITIAL_HOSTS"
    echo "">$HOSTS_PATH
fi

cat $NEW_HOSTS >> $HOSTS_PATH

# Clean up old downloads
echo "Removing cache..."
rm $NEW_HOSTS*
echo "Done!"
exit 0