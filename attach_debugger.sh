#!/bin/sh
progstr=eagleemu
progpid=`pgrep -o $progstr`
while [ "$progpid" = "" ]; do
  progpid=`pgrep -o $progstr`
done

sudo gdb -p $progpid -ex continue
