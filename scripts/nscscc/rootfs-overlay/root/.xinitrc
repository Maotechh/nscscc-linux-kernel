#!/bin/sh
export HOME=/root USER=root LOGNAME=root DISPLAY=:0
fbsetroot -solid white
feh --bg-center /root/miku.png &
xterm -geometry 50x14+20+520 -fa "DejaVu Sans Mono" -fs 9 \
    -title "NSCSCC LoongArch32 Reduced" &
exec fluxbox
