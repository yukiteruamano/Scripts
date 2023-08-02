#!/usr/bin/env python

__module_name__ = "Rhythmbox Spam Music"
__module_version__ = "1.0"
__module_description__ = "Otorga informacion sobre la reproduccion de musica en Rhythmbox"


import hexchat
import commands


def mp3_info(word, word_eol, userdata):
    artista = commands.getoutput("rhythmbox-client --print-playing-format %ta")
    titulo = commands.getoutput("rhythmbox-client --print-playing-format %tt")
    album = commands.getoutput("rhythmbox-client --print-playing-format %at")
    duracion = commands.getoutput("rhythmbox-client --print-playing-format %td")
    hexchat.command("me || Rhythmbox: " + artista + " - " +  titulo + " - (" + duracion + ") - " + album +" ||"  )
    return hexchat.EAT_ALL


hexchat.hook_command("nowplay", mp3_info, help="Despliega la informacion de la reproduccion en Rhythmbox")


print "Rhythmbox Spam Music loaded for HexChat IRC"
