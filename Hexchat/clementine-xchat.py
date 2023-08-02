__module_name__ = "Clementine MP3"
__module_version__ = "1.1"
__module_description__ = "Otorga informacion sobre la reproduccion de musica en Clementine"

from dbus import Bus, DBusException
import xchat
import commands
bus = Bus(Bus.TYPE_SESSION)

def check_clementine():
    try:
         return bus.get_object('org.mpris.clementine', '/Player')
    except DBusException:
        print "\x02Clementine no esta ejecutandose, o ha ocurrido un error en el subsistema DBUS"
        return None

def mp3_info(word, word_eol, userdata):

    check_clementine()
    artist = commands.getoutput("qdbus org.mpris.clementine /Player GetMetadata | grep artist: | sed 's/artist://'")
    titulo = commands.getoutput("qdbus org.mpris.clementine /Player GetMetadata | grep title: | sed 's/title://'")
    album = commands.getoutput("qdbus org.mpris.clementine /Player GetMetadata | grep album: | sed 's/album://'")
    bitrate = commands.getoutput("qdbus org.mpris.clementine /Player GetMetadata | grep audio-bitrate: | sed 's/audio-bitrate://'")
    genero = commands.getoutput("qdbus org.mpris.clementine /Player GetMetadata | grep genre: | sed 's/genre://'")

    xchat.command("me || Clementine: " + artist + " - " +  titulo + " - " + album + " - " + bitrate + " kbps - " + genero + " ||" )

    return xchat.EAT_ALL

xchat.hook_command("mp3", mp3_info, help="Despliega la informacion de la reproduccion en Clementine")

print "Clementine MP3 loaded for XChat IRC"
