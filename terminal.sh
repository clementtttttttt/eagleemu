clear
stty -F /dev/ttyUSB0 raw crtscts 500000 clocal cstopb
picocom /dev/ttyUSB0 -p 2 --baud 500000 --omap crlf --imap lfcrlf -f h -d 8 -p 1
stty -F /dev/ttyUSB0 raw crtscts 500000 clocal cstopb

