#!/bin/bash
###############################################################################
# Author  : Kevin Zhou<zrzxlfe@gmail.com>
# Date    : 2020-06-18
# Version : v1.0
# Abstract: Manage user mode linux
# Usages  : 1. UML start: ./runUML.sh [reset | a | u | S | T]
#           2. UML stop : via cmd 'halt' or Ctrl+D (Must be root logined)
#           3. CMD must be run by root: apt git etc.
# Notes   : Even though run 'git clone' by root, but root don't own these files.
#           The permissions and ownership that all of clone files are same as
#           directly run 'git clone' by the user that run UML program.
# History : Please check the end of file.
###############################################################################
ws_path=$(pwd)
uml_exe=$ws_path/UML-4.19.195
uml_ip_address='10.1.0.10'
host_ip_address='10.1.0.1'
tap_iface_name='tapUML'
host_share_path="$ws_path/uml-share-with-host" # Must use "" not '' if has $

rootfs_dir_name='rootfs.dir'
rootfs_img_name='rootfs.img'

memory_cfg_args='rw mem=512M'
rootfs_cfg_args="ubda=$ws_path/$rootfs_img_name.cow,$ws_path/$rootfs_img_name"
init_config_args="init=/uml_init.sh"
slirp_net_cfg_args="eth0=slirp,,$ws_path/slirp-1.0.17"
tuntap_net_cfg_args="eth1=tuntap,$tap_iface_name,,"


function setup_uml_init_sh() {
export uml_ip_address host_ip_address
cat > uml_init.sh << EOF
#!/bin/sh

hostname -b -F /etc/hostname

echo "setup file system..."
mount -t proc proc proc/
mount -t sysfs sys sys/

echo "setup networking..."
ifconfig lo up
ifconfig eth1 ${uml_ip_address} netmask 255.255.255.0 up
ifconfig eth0 10.0.0.10 netmask 255.255.255.0 broadcast 10.0.0.255 up
route add default gw 10.0.0.1

echo "start ssh service in the background..."
/etc/init.d/ssh start &

echo "setup host share directory..."
EOF

[ ! -d $host_share_path ] && mkdir -p $host_share_path
[ ! -s $rootfs_dir_name/tini-0.19.0 ] && cp tini-0.19.0 $rootfs_dir_name

# Mount UML's /mnt onto host's directory
echo "mount none /mnt -t hostfs -o $host_share_path" >> uml_init.sh
echo -e "echo [\`date\`] Enjoy UML! > /mnt/uml_is_ready\n" >> uml_init.sh

echo "su -l root" >> uml_init.sh
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
		S)  # 只能访问公网，无法访问本机
			inet_config_args=$slirp_net_cfg_args
		;;
		T)  # 只能访问本机，无法访问公网
			# 注意：！！！ 
			# 1）此种方式进入uml后即可与主机进行通信（在root用户环境下可以ping通主机，主机也能ping通UML），
			#    但uml无法访问公网，还需要借助网桥才行(https://blog.csdn.net/qq_34160841/article/details/104901127)
			# 2）在UML中貌似无法通过Ctrl-C来退出程序，此时只得从主机侧新开一个终端kill掉uml(sudo killall UML-4.19.195)
			# 3）uml_init.sh 中已配置自动启动 sshd 但启动时间较长，此外启动sshd之后，退出UML时也将比较耗时，只得外部kill
			# 4）从UML侧无法通过ssh连接主机，但从主机侧可以通过ssh连接UML（连接UML之后却可以再反向ssh主机，暂不知为何）
			inet_config_args="eth1=tuntap,,,$host_ip_address"
			uml_exe="sudo $uml_exe"
		;;
		*)  # 结合以上 S T 两种方式，配置双网卡，一个只与主机通信，一个用于与公网通信
			[[ $EUID -ne 0 ]] && echo "This operation must be run as root." && exit 1
			type tunctl >/dev/null 2>&1
			if [ $? -ne 0 ]; then
				echo "uml-utilities not installed. if you want to install?(y/n)"
				read -t 5 ans
				[ "$ans" != "y" ] && exit 1
				sudo apt install uml-utilities
			fi
			if [[ `ifconfig $tap_iface_name 2>&1` = *"Device not found"* ]]; then
				sudo tunctl -t $tap_iface_name
				sudo ifconfig  $tap_iface_name ${host_ip_address}
			fi
			uml_exe="sudo $uml_exe"
			inet_config_args="$slirp_net_cfg_args $tuntap_net_cfg_args"
		;;
	esac

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

	# 解决UML报错(https://www.cnblogs.com/duanxz/p/3567068.html) 
	# 'UML ran out of memory on the host side! ... vm.max_map_count has been reached.'
	sudo sh -c 'sysctl -w vm.max_map_count=524288 && sysctl -a|grep vm.max_map_count'

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
# https://jingyan.baidu.com/article/380abd0a0b35501d91192c69.html
###############################################################################
