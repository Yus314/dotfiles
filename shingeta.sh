#!/bin/bash
echo "OK1" >> ~/shingetalog.txt
fcitx5&
echo "OK3" >> ~/shingetalog.txt 
sleep 20
XREMAP_CONFIG="$HOME/dotfiles/shingeta.yaml"
echo "OK4" >> ~/shingetalog.txt 
while true; do
    echo "OK4" >> ~/shingetalog.txt 
    FCITX_STATE=$(fcitx5-remote)
    echo "OK5" >> ~/shingetalog.txt 
    if [ "$FCITX_STATE" -eq 2 ]; then
	if ! pgrep -x "xremap" > /dev/null; then
	    xremap "$XREMAP_CONFIG" &
	fi
    else
	if pgrep -x "xremap" > /dev/null; then
	    pkill -x "xremap"
	fi
    fi
    sleep 0.1
done
