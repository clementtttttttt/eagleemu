trap "trap - SIGTERM && kill -- -$$" SIGINT SIGTERM EXIT
socat -d -d pty,raw,echo=0,crtscts=1,link=./eagleterm pty,crtscts=1,raw,echo=0,link=./eagleterm_rx > /dev/null  2>socatlog &

echo STARTING EAGLEEMU
bin/Debug/eagleemu  eagleterm_rx -a ./tetris.aqxe &



until [ -e ./eagleterm_rx ]
do
     sleep 0.5
done


picocom ./eagleterm_rx -f h --omap crlf --imap lfcrlf -d 8 -p 1
killall eagleemu -9
