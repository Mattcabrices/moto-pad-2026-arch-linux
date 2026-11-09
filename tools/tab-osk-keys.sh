sudo -u matt env DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus gsettings list-recursively sm.puri.Squeekboard 2>&1 | head
