U="sudo -u matt env DISPLAY=:0 XAUTHORITY=/home/matt/.Xauthority"
for id in $($U xinput list | grep -i himax | grep -oE "id=[0-9]+" | cut -d= -f2); do echo "id $id: $($U xinput list-props $id | grep "Coordinate Transformation Matrix" | cut -d: -f2)"; done
$U xrandr --query | grep DSI-1
