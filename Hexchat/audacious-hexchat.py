#!/usr/bin/env python3
# -*- coding: utf-8 -*-

__module_name__ = "Audacious2 MP3"
__module_version__ = "1.1"
__module_description__ = "HexChat Spam Audacious"


import hexchat
import subprocess


def mp3_info(word, word_eol, userdata):

    artist = subprocess.getoutput("audtool --current-song-tuple-data artist")
    titulo = subprocess.getoutput("audtool --current-song-tuple-data title")
    album = subprocess.getoutput("audtool --current-song-tuple-data album")
    bitrate = subprocess.getoutput("audtool --current-song-tuple-data bitrate")
    genero = subprocess.getoutput("audtool --current-song-tuple-data genre")
    calidad = subprocess.getoutput("audtool --current-song-tuple-data quality")
    duracion = subprocess.getoutput("audtool --current-song-length")

    hexchat.command("me || Audacious: (" + artist + " - " + titulo + " - " +
                    album + " - " + duracion + ") - (" + bitrate + " kbps - " +
                    genero + " - " + calidad + ") ||")
    return hexchat.EAT_ALL

hexchat.hook_command("aump3", mp3_info, help="HexChat Spam Audacious")

print("Audacious MP3 loaded for HexChat IRC")
