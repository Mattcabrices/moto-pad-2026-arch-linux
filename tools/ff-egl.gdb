set pagination off
set breakpoint pending on
handle SIGSYS SIGPIPE SIG32 SIG33 SIG34 SIG35 SIG36 SIG37 SIG38 SIG39 SIG40 nostop noprint pass
break eglCreateContext
commands
silent
printf "CREATE cfg=%p share=%p attribs:", $x1, $x2
set $i = 0
while $i < 24 && ((int*)$x3)[$i] != 0x3038
  printf " %#x", ((int*)$x3)[$i]
  set $i = $i + 1
end
printf "\n"
finish
end
break eglMakeCurrent
commands
silent
printf "MAKECURRENT draw=%p read=%p ctx=%p\n", $x1, $x2, $x3
finish
end
run
