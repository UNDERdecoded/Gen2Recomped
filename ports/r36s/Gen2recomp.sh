#!/bin/bash
XDG_DATA_HOME="$HOME/.local/share"
EXEDIR="$(dirname "$0")/gen2recomp"
cd "$EXEDIR"

source /roms/ports/PortMaster/control.txt
[ -f "${controlfolder}/modded_controls" ] && source "${controlfolder}/modded_controls"

export LD_LIBRARY_PATH="$EXEDIR/libs:$LD_LIBRARY_PATH"
export SDL_GAMECONTROLLERCONFIG="$sdl_controllerconfig"

export LIBGL_ES=2
export LIBGL_GL=21

$GPTOKEYB "love" -c "./gen2recomp.gptk" &
./love .

$ESUDO killall -9 gptokeyb
