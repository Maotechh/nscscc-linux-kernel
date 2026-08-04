#!/bin/sh

export HOME=/root USER=root LOGNAME=root DISPLAY=:0

wallpaper=/usr/share/backgrounds/nscscc-hatsune-miku.jpg
if [ -r "$wallpaper" ]; then
    feh --no-fehbg --bg-fill "$wallpaper" || \
        fbsetroot -solid "#183844"
else
    fbsetroot -solid "#183844"
fi

xterm -geometry 50x14+20+520 -fa "DejaVu Sans Mono" -fs 9 \
    -title "NSCSCC LoongArch32 Reduced" &
exec fluxbox
