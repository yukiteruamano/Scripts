#!/usr/bin/env bash

doas freshclam

/usr/local/bin/clamscan -i -l /home/yukiteru/clamscan.log -r /home/yukiteru --exclude-dir=/home/yukiteru/NFS