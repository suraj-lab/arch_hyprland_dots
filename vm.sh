#!/bin/bash

virsh --connect qemu:///system start Gaming
sleep 2
looking-glass-client -m 97 &
exit
