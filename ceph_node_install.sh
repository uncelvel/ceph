#/bin/bash
# Author: canhdx@nhanhoa.com
# Date: 25/10/2017

# This script will be call from ceph_admin_install.sh on Admin node

# [ $# -lt 2 ] && echo "wrong number of args" && exit 1
set_hostname(){
	hostname set-hostname "$2"
	init 6
}

create_cephuser(){
	echo create_cephuser "$1" "$2"
	# Add User setup
	useradd -d /home/"$1" -m $1
	echo "$2" | passwd  "$1" --stdin
	# Grant sudo privileges
	echo "$1 ALL = (root) NOPASSWD:ALL" >> /etc/sudoers

	# sed -i "s|\#includedir \/etc\/sudoers.d|\includedir \/etc\/sudoers.d|g" /etc/sudoers
	# echo "$1 ALL = (root) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/"$1"
	# chmod 0440 /etc/sudoers.d/"$1"
}

check_install_ceph(){
	# yum remove ceph ceph-radosgw libceph* librbd* librados* -y
	# Check Install ceph
	new_v_ceph="$(yum --disablerepo="*" --enablerepo="Ceph*" list available | grep ceph-resource-agents | awk '{print $2}' | cut -d ':' -f2 | rev | cut -c 7- | rev)"  
	now_v_ceph="$(ceph -v | awk '{print $3}')"
	

	if [ "$now_v_ceph" == "" ] ; then 
		echo "On $(hostname) ceph doesnt install"
	else
		if [ "$now_v_ceph" = "$new_v_ceph" ] ; then 
			echo "On $(hostname) ceph $now_v_ceph already installed the last version!"
		else
			echo "On  $(hostname) ceph already installed old version!"
		fi

		if [ "$(ceph -s | grep health | awk '{print $1}')" == "health" ] ;  then
			echo "Node $(hostname) in Cluster"
		fi
	fi

	# Check OSD
}

requirement(){
		# date -s "$(curl -s --head http://google.com | grep ^Date: | sed 's/Date: //g') -0500"
		yum install screen dos2unix pssh sshpass git wget telnet fio iperf3 epel-release yum-plugin-priorities
		# Disable firewalld 	
		systemctl disable firewalld
		systemctl stop firewalld
		# Disabled SELinux
		sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config
		yum update -y
}

setup_ntpd(){
	if [ "$1" == "1" ] ; then 
		echo "${green} Setup NTPD on $(hostname) ${reset}" && sleep 2s
		yum install ntp ntp-doc ntpdate -y
		cp /usr/share/zoneinfo/Asia/Ho_Chi_Minh  /etc/localtime
		systemctl stop ntpd
		firewall-cmd --add-service=ntp --permanent
		firewall-cmd --reload
	elif [ "$1" == "2" ] ; then
		systemctl start ntpd
		systemctl enable ntpd
		sync_time="$(timedatectl | grep synchronized | awk '{print $3}')"
		if [ "$sync_time" == "yes" ] ; then 
			hwclock --systohc
			date -R
			ntpq -p
		else
			systemctl restart ntpd
			sync_time2="$(timedatectl | grep synchronized | awk '{print $3}')"
			if [ "$sync_time2" == "yes" ] ; then 
				hwclock --systohc
				date -R
				ntpq -p
			else
				echo "Install NTPD Failed"
			fi
		fi
	else 
		echo "Wrong syntax"
	fi
}

m_cephinstall(){
	#Cleaning Previous Ceph Environment 
	yum remove ceph-release ceph ceph-radosgw libceph* librbd* librados* -y 
	rm -rf /etc/yum.repos.d/ceph.repo.rpmsave
	yum update -y
	yum install ceph ceph-radosgw -y
	result="$(ceph -v |awk '{print $1}')"
	if [ "$result" == "ceph" ] ; then
		echo "Install ceph on $(hostname) Successfully"
	else
		echo "Install ceph on $(hostname) Failed"
	fi
}

case "$1" in
	check_install_ceph)
		check_install_ceph
		;;
	requirement)
		requirement
		;;
	set_hostname)
		set_hostname
		;;
	create_cephuser)
		create_cephuser "$2" "$3"
		echo create_cephuser "$2" "$3"
		;;
	setup_ntpd)
		if [ "$2" == "1" ]; then 
			setup_ntpd 1
		elif [ "$2" == "2" ]; then
			setup_ntpd 2
		fi
		;;
	m_cephinstall)
		m_cephinstall
		;;
	*)
		echo $"Usage: $0 {install_requirement|set_hostname|check_install_ceph|create_cephuser|setup_ntpd|condrestart|status}  <option>"
		;;
esac
