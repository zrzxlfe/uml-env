#!/bin/sh

hostname -b -F /etc/hostname

echo "setup file system..."
mount -t proc proc proc/
mount -t sysfs sys sys/

echo "setup networking..."
ifconfig eth0 10.0.0.10 netmask 255.255.255.0 broadcast 10.0.0.255
route add default gw 10.0.0.1

echo "setup host share directory..."
mount none /mnt -t hostfs -o /home/kevin/workspace/temp/UML/uml-env/uml-share-with-host
echo [`date`] Enjoy UML! > /mnt/uml_is_ready

su -l uml
exec /sbin/init
