#!/bin/sh

export HOME=/root USER=root LOGNAME=root DISPLAY=:0
xterm -geometry 56x18+12+12 -fa "DejaVu Sans Mono" -fs 9 \
    -title "NSCSCC LoongArch32 Reduced" &
exec fluxbox
