U="sudo -u matt env DISPLAY=:0 XAUTHORITY=/home/matt/.Xauthority"
$U xinput list --name-only
id=$($U xinput list | grep -iE "himax|touch" | grep -iv keyboard | grep -oE "id=[0-9]+" | head -1 | cut -d= -f2)
echo "touch id: $id"
[ -n "$id" ] && $U xinput --map-to-output "$id" DSI-1 && echo mapped
