#!/bin/bash

# Function to check if the virtual machine is running
check_vm_status() {
    vm_status=$(virsh --connect qemu:///system list --all | grep " Work " | awk '{ print $3 }')
    if [ "x$vm_status" == "x" ]; then
        return 1
    elif [ "$vm_status" == "running" ]; then
        return 0
    else
        return 2
    fi
}

# Function to start the virtual machine
start_vm() {
    virsh --connect qemu:///system start Work
    sleep 2
}

# Function to start the Looking Glass client
start_looking_glass() {
    looking-glass-client -m 97 &
}

# Main script logic
if check_vm_status; then
    echo "Work VM is already running."
    start_looking_glass
else
    echo "Starting Work VM..."
    start_vm
    sleep 2  # Wait for VM to fully start
    start_looking_glass
fi
