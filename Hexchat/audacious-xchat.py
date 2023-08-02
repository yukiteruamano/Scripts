#!/usr/bin/env python
# -*- coding: utf-8 -*-

__module_name__ = "Audacious2 MP3"
__module_version__ = "1.0"
__module_description__ = "Otorga informacion sobre la reproduccion de musica en Audacious"

import xchat
import commands

def mp3_info(word, word_eol, userdata):

    artist = commands.getoutput("audtool --current-song-tuple-data artist")
    titulo = commands.getoutput("audtool --current-song-tuple-data title")
    album = commands.getoutput("audtool --current-song-tuple-data album")
    bitrate = commands.getoutput("audtool --current-song-tuple-data bitrate")
    genero = commands.getoutput("audtool --current-song-tuple-data genre")
    calidad = commands.getoutput("audtool --current-song-tuple-data quality")
    duracion = commands.getoutput("audtool --current-song-length")

    xchat.command("me || Audacious: (" + artist + " - " +  titulo + " - " + album + " - " + duracion +") - ("  + bitrate + " kbps - " + genero + " - " + calidad + ") ||"  )
    return xchat.EAT_ALL

xchat.hook_command("aump3", mp3_info, help="Despliega la informacion de la reproduccion en Audacious")

print "Audacious MP3 loaded for XChat IRC"
