#!/bin/sh
#
# Script to install a fresh container with some initial configuration.
#
# Last update: Sep 18 2013, for Fedora 19

if [ "`id -un`" != "root" ]; then
    echo "Error: this script needs to run as root"
    exit 1
fi

if [ "$#" -ne "1" -a "$#" -ne "2" ]; then
    echo "Usage: $0 <directory> [<version>]"
    exit 1
fi
parent=`dirname "$1"`
root=`readlink -f "$1"`
version="$2"

if [ ! -d "$parent" ]; then
    echo "Error: no such directory: $parent"
    exit 1
fi

if [ -e "$root" ]; then
    echo "Error: $1 already exists"
    exit 1
fi

df -T "$parent" | grep -q btrfs || {
    echo "Error: $root is not on a btrfs"
    exit 1
}

# See not about auditing in:
# https://fedoraproject.org/wiki/Features/SystemdLightweightContainers
grep -q audit=0 /proc/cmdline || {
    echo "Error: auditing is not disabled"
    exit 1
}

if [ -z "$version" ]; then
    version="`rpm -q fedora-release | sed -e 's/^fedora-release-//' -e 's/-.*$//'`"
fi
echo "Creating new rootfs for Fedora $version in $root ..."

btrfs subvolume create "$1"

packages="fedora-release @core vim gcc gcc-c++ gdb net-tools tar dhclient
          git python-devel python-pip python3-devel python3-pip
          --exclude NetworkManager,sendmail,firewalld,plymouth"

yum -y --releasever=$version --nogpg --installroot="$root" \
    --disablerepo='*' --enablerepo=fedora install $packages

# Some initial guest configuration
hostname=`basename "$root"`
echo "$hostname" > "$root/etc/hostname"

# https://bugzilla.redhat.com/show_bug.cgi?id=966807
sed -i -e 's/^\(.*pam_loginuid.*\)$/#\1/' "$root/etc/pam.d/login"
sed -i -e 's/^\(.*pam_loginuid.*\)$/#\1/' "$root/etc/pam.d/remote"

# enable dhclient
cat << EOM > "$root/usr/lib/systemd/system/dhclient.service"
[Unit]
Description=DHCP client
Before=network.target
Wants=network.target

[Service]
EnvironmentFile=/etc/sysconfig/network
ExecStartPre=/bin/rm -f /var/run/dhclient.pid
ExecStart=/sbin/dhclient -d eth0 -H $HOSTNAME

[Install]
WantedBy=multi-user.target
EOM
ln -s "/usr/lib/systemd/system/dhclient.service" \
    "$root/etc/systemd/system/multi-user.target.wants/dhclient.service"

# Install some initial user configuration, if available
if [ "$USERNAME" = "root" ]; then
    USERNAME="$SUDO_USER"
fi
if [ "$USERNAME" != "root" ]; then
    uid=`getent passwd "$USERNAME" | awk -F: '{print $3}'`
    homedir=`getent passwd "$USERNAME" |awk -F: '{print $6}'`
    password=`getent shadow "$USERNAME" | awk -F: '{print $2}'`
    systemd-nspawn -D "$root" usermod -p "$password" root
    systemd-nspawn -D "$root" useradd "$USERNAME" -u "$uid" -p "$password"
    systemd-nspawn -D "$root" gpasswd -a "$USERNAME" wheel
    files=".ssh .ssh/authorized_keys .vimrc .bashrc .gitconfig"
    tar cCf "$homedir" - --no-recursion $files | \
        tar xvpCf "$root/home/$USERNAME" -
fi
