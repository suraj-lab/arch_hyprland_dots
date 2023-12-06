#!/bin/bash


tmp=$(virsh --connect qemu:///system list  | grep " Gaming " | awk '{ print $3}')

if ([ "x$tmp" == "x" ] || [ "x$tmp" != "xrunning" ] || ! [ -f /dev/shm/looking-glass ]);
then
	virsh --connect qemu:///system start Gaming
	sleep 2
	looking-glass-client -m 97 &
	
elif ([ "x$tmp" = "running" ] || [ -f /dev/shm/looking-glass ]);
then
	looking-glass-client -m 97 &
fi

end
