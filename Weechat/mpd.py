"""
Author:
    Jose Maldonado aka YukiteruAmano <yukiteru.amano AT gmx DOT com>

What it does:
    This script shows the currently played song in mpd

Usage:
    /mpd - Displays the songname

Released under GNU GPL v3 or newer
"""
import weechat as wc
from os import popen

wc.register("mpd", "YukiteruAmano", "0.1", "GPL3", "Now playing spammer for mpd", "", "")

def np(data, buffer, args):
    tempinfo = popen('mpc -f "%artist% - %title% (%time%) - %album% - %genre%"').readline().rstrip()
    all = '/me escuchando: ' + tempinfo
    wc.command(wc.current_buffer(), all)
    return 0

wc.hook_command("mpd", "now playing", "", "", "", "np", "")

