#!/bin/bash
###############################################################################
# Author  : Kevin Zhou<zrzxlfe@gmail.com>
# Date    : 2020-06-18
# Version : v1.0
# Abstract: Manage user mode linux
# Usages  : 1. UML start: ./runUML.sh [reset | a | u]
#           2. UML stop : via cmd 'halt' or Ctrl+D (Must be root logined)
#           3. CMD must be run by root: apt git etc.
# Notes   : Even though run 'git clone' by root, but root don't own these files.
#           The permissions and ownership that all of clone files are same as
#           directly run 'git clone' by the user that run UML program.
# History : Please check the end of file.
###############################################################################
ws_path=$(pwd)
uml_exe=$ws_path/UML-4.19.95
host_share_path="$ws_path/uml-share-with-host" # Must use "" not '' if has $

rootfs_dir_name='rootfs.dir'
rootfs_img_name='rootfs.img'

memory_cfg_args='rw mem=512M'
rootfs_cfg_args="ubda=$ws_path/$rootfs_img_name.cow,$ws_path/$rootfs_img_name"
inet_config_args="eth0=slirp,,$ws_path/slirp-1.0.17"
init_config_args="init=/uml_init.sh"


function setup_uml_init_sh() {
cat > uml_init.sh << EOF
#!/bin/sh

hostname -b -F /etc/hostname

echo "setup file system..."
mount -t proc proc proc/
mount -t sysfs sys sys/

echo "setup networking..."
ifconfig lo up
ifconfig eth0 10.0.0.10 netmask 255.255.255.0 broadcast 10.0.0.255 up
route add default gw 10.0.0.1

echo "setup host share directory..."
EOF

[ ! -d $host_share_path ] && mkdir -p $host_share_path
[ ! -s $rootfs_dir_name/tini-0.19.0 ] && cp tini-0.19.0 $rootfs_dir_name

# Mount UML's /mnt onto host's directory
echo "mount none /mnt -t hostfs -o $host_share_path" >> uml_init.sh
echo -e "echo [\`date\`] Enjoy UML! > /mnt/uml_is_ready\n" >> uml_init.sh

echo "su -l uml" >> uml_init.sh
if [ "$1" = "a" -o "u" = "$1" ]; then
	echo "exec /tini-0.19.0 /bin/sh" >> uml_init.sh
else
	# Could to stop UML by 'halt', and there is no 'Aborted (core dumped)' error
	echo "exec /sbin/init" >> uml_init.sh
fi

chmod +x uml_init.sh
sudo  cp uml_init.sh $rootfs_dir_name
}

function main() 
{
	case $1 in
		reset) rm -f *.cow *.img ; ls -F -I resources | grep "/$" | xargs rm -rf ; exit 0 ;;
		a) 
			rootfs_dir_name='alpine-3.14-minirootfs'
			if [ ! -d $rootfs_dir_name ]; then
				mkdir -p $rootfs_dir_name
				tar -xf $ws_path/resources/alpine-minirootfs-*.tar.gz -C $rootfs_dir_name
				setup_uml_init_sh $1
			fi
		;;
		u)
			rootfs_dir_name='ubuntu-20.04-baserootfs'
			if [ ! -d $rootfs_dir_name ]; then
				mkdir -p $rootfs_dir_name
				sudo tar -xpf $ws_path/resources/ubuntu-base-*.tar.gz -C $rootfs_dir_name
				setup_uml_init_sh $1
			fi
		;;
		*)
			if [ ! -s $rootfs_img_name ]; then
				7z x $ws_path/resources/ubuntu-rootfs.7z
				mv ubuntu-rootfs.img $rootfs_img_name
			fi
			if [ ! -s $rootfs_img_name.cow ]; then
				[ ! -d $rootfs_dir_name ] && mkdir -p $rootfs_dir_name
				sudo mount  $rootfs_img_name $rootfs_dir_name
				setup_uml_init_sh $1
				sudo umount $rootfs_dir_name && rmdir $rootfs_dir_name
			fi
		;;
	esac

	if [ "$1" = "a" -o "u" = "$1" ]; then
		if [ ! -f /dev/root ]; then
			host_rootfs_partation=`df | awk '{if ("/" == $NF) print $1}'`
			sudo ln -sf $host_rootfs_partation /dev/root
		fi
		rootfs_cfg_args="root=/dev/root rootfstype=hostfs rootflags=$ws_path/$rootfs_dir_name"
	fi

	echo \
	$uml_exe $memory_cfg_args $rootfs_cfg_args $inet_config_args $init_config_args

	$uml_exe $memory_cfg_args $rootfs_cfg_args $inet_config_args $init_config_args
}

main $@

###############################################################################
# Author        Date        Version    Abstract
#------------------------------------------------------------------------------
# Kevin Zhou   2020-06-18   v1.0       Initial version create
#------------------------------------------------------------------------------
# references:
# https://github.com/Xe/furry-happiness
# https://github.com/shaswata56/User_Mode_Linux
# https://www.cnblogs.com/dream397/p/14251536.html
# https://www.cnblogs.com/dream397/p/14251617.html
# https://blog.csdn.net/gogofly_lee/article/details/2146602
###############################################################################
