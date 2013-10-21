#!/bin/sh
#
# Script to create a new vm

if [ "`id -un`" != "root" ]; then
    echo "Error: this script needs to run as root"
    exit 1
fi

if [ "$#" -ne "2" ]; then
    echo "Usage: $0 <template> <name>"
    exit 1
fi
template=`readlink -f "$1"`
root=`readlink -f "$2"`

if [ ! -d "$template" ]; then
    echo "Error: no such directory: $template"
    exit 1
fi
if [ -e "$root" ]; then
    echo "Error: $root already exists"
    exit 1
fi

btrfs subvolume snapshot "$template" "$root"
host=`basename "$root"`
echo "$host" > "$root/etc/hostname"
echo "HOSTNAME=$host" >> "$root/etc/sysconfig/network"

tempxml=".template.xml.$$"
excpath=`readlink -f $0`
template=`dirname "$excpath"`/template.xml
sed -e "s,\$name,$host,g" -e "s,\$root,$root,g" < "$template" > "$tempxml"
virsh -c lxc:/// define "$tempxml"
virsh -c lxc:/// start "$host"
rm -f "$tempxml"
