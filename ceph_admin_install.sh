#/bin/bash
# Author: canhdx@nhanhoa.com
# Date: 25/10/2017

begin=$(date +%s) 

# Define all parametters
red=`tput setaf 1`
green=`tput setaf 2`
reset=`tput sgr0`

DIR="$(pwd)"
INPUT="hosts.csv"
INPUT2="temp_hosts.csv"
# Password root all Server
password="passla123" 
# Ceph user create for ceph-deploy
CEPHUSER="cephuser"
CEPHUSER_PWD="$(openssl rand -base64 10)" # CEPHUSER_PWD="passla123"  
HOSTS=(); MON=(); MDS=(); RGW=(); OSD=(); NTPD=(); DISK=(); 
# Megabyte (MB) Journal size for OSD of CEPH Cluster
journal_size="2048" 



# Local prepare for scripts
preinstall(){
	echo "${red} Pre_install ${reset}" && sleep 2s

	# Install requirement software
	echo "${green} Install requirement software ${reset}" && sleep 2s
	#Update time without NTPD
	date -s "$(curl -s --head http://google.com | grep ^Date: | sed 's/Date: //g') -0500"
	yum update -y
	yum install -y screen dos2unix pssh sshpass git wget telnet fio iperf3 epel-release yum-plugin-priorities 
	yum update -y

	# Disable firewall and SElinux	
	echo "${green} Disable firewall and SElinux ${reset}" && sleep 2s
	systemctl disable firewalld
	systemctl stop firewalld
	# Disabled SELinux
	sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config

	# Enable X-forward
	echo "${green} Enable X-forward ${reset}" && sleep 2s
	# yum install "@X Window System" xorg-x11-xauth xorg-x11-fonts-* xorg-x11-utils -y
	# sed -i 's/#X11Forwarding no/X11Forwarding yes/g' /etc/ssh/sshd_config
	# systemctl restart sshd

	# Prepare config
	echo "${green} Prepare config ${reset}" && sleep 2s
	yes | cp "$DIR"/conf/ceph.conf.bk "$DIR"/conf/ceph.conf
	yes | cp "$DIR"/conf/ntp.conf.bk  "$DIR"/conf/ntp.conf

}

# Read host.csv file to get parameters
readfile(){	
	echo "${green} Read_csv_file ${reset}" && sleep 2s
	[ ! -f "$INPUT" ] && { echo "$INPUT file not found"; exit 99; }
	column -t -s',' "$DIR"/hosts.csv && sleep 10s
	tail -n +2 "$INPUT" > "$INPUT2"
	i=0
	# awk 'NR>1' "$INPUT" | while IFS="," read  -r host ip_public ip_cluster f_admin f_mon f_mds f_rgw f_osd f_ntpd disk_journal disk_osd
	while IFS="," read  -r host ip_public ip_cluster f_admin f_mon f_mds f_rgw f_osd disk_journal disk_osd f_ntpd os
	do 
		if [ "$i" == 0 ] ; then 
			# Ntpd config file
			echo "${green} Echo NTPD conf ${reset}" && sleep 2s
			SUBNETMASK="$(ipcalc -mn "$ip_public" | grep NETMASK | cut -d "=" -f2)"
			sed -i "s|restrict 172.16.0.0 mask 255.255.255.0 nomodify notrap|restrict $(echo "$ip_public" | cut -d "/" -f1) mask $SUBNETMASK nomodify notrap|g" "$DIR"/conf/ntp.conf
			sed -i "s|\#allow 172.16.0.0\/20|\#allow $ip_public|g" "$DIR"/conf/ntp.conf	
				
			# Host file
			echo "${green} Prepare hosts file ${reset}" && sleep 2s
			echo "$(echo "$ip_public" | cut -d "/" -f1)" "$host"  > "$DIR"/conf/hosts
			
			# SSH config file 
			echo "${green} Prepare sshconfig file ${reset}" && sleep 2s
			echo Host \* > "$DIR"/conf/sshconfig 								#|
        	echo $'\t'StrictHostKeyChecking no >> "$DIR"/conf/sshconfig 		#|--> Disabled Host checking
        	echo $'\t'UserKnownHostsFile=/dev/null >> "$DIR"/conf/sshconfig 	#|
        	echo $'\t'LogLevel QUIET >> "$DIR"/conf/sshconfig 					#|
        	echo >> "$DIR"/conf/sshconfig
			echo Host "$host" >> "$DIR"/conf/sshconfig
			echo $'\t'Hostname "$host" >> "$DIR"/conf/sshconfig
			echo $'\t'User "$CEPHUSER" >> "$DIR"/conf/sshconfig
			
			# Ceph config file
			echo "${green} Prepare cephconfig file ${reset}" && sleep 2s
			sed -i "s|25600|$journal_size|g" "$DIR"/conf/ceph.conf	
			sed -i "s|public network = 172.16.0.0\/24|public network = $ip_public|g" "$DIR"/conf/ceph.conf
			sed -i "s|cluster network = 10.0.0.0\/24|cluster network = $ip_cluster|g" "$DIR"/conf/ceph.conf
		else
			echo "$(echo "$ip_public" | cut -d "/" -f1)" "$host"  >> "$DIR"/conf/hosts
			echo Host "$host" >> "$DIR"/conf/sshconfig
			echo $'\t'Hostname "$host" >> "$DIR"/conf/sshconfig
			echo $'\t'User "$CEPHUSER" >> "$DIR"/conf/sshconfig
		fi
		
		HOSTS+=("$host")
		
		if [ "$f_mon" -eq "1" ] ; then
			MON+=("$host")
		fi
		
		if [ "$f_mds" == "1" ] ; then
			MDS+=("$host")
		fi
		
		if [ "$f_rgw" == "1" ] ; then
			RGW+=("$host")
		fi
		
		if [ "$f_osd" == "1" ] ; then
			OSD+=("$host")
			# DISK2+=("$host"_"$disk_journal"_"$disk_osd")
			# Process Disk for `ceph-deploy osd create`
			IFS='_' read -r -a arr_disk <<< "$disk_osd"
			for i in $(seq 0 $(expr ${#arr_disk[@]} - 1))
			do
				if [ "$disk_journal" == "0" ]; then
					DISK+=("$host":"${arr_disk[$i]}")
				else
					DISK+=("$host":"${arr_disk[$i]}":/dev/"$disk_journal")
				fi
			done
		fi
		
		if [ "$f_ntpd" == "1" ] ; then
			NTPD+=("$host")
		fi	

		let "i++"
	done < "$INPUT2"

	echo "${green} Copy SSH config file ${reset}" && sleep 2s
	mkdir -p ~/.ssh/
	cp "$DIR"/conf/sshconfig ~/.ssh/config
	chmod 440 ~/.ssh/config
	rm -rf "$INPUT2"

	echo "${green} Result of host.csv for CEPH cluster ${reset}" && sleep 2s
	echo HOSTS ${HOSTS[@]}
	echo MON ${MON[@]}
	echo MDS ${MDS[@]}
	echo RGW ${RGW[@]}
	echo OSD ${OSD[@]}
	echo DISK ${DISK[@]}
	echo NTPD ${NTPD[@]}
}

confirm_exit(){
    # call with a prompt string or use a default
    read -r -p "${1:-Are you sure? [y/N]} " response
    case "$response" in
        [yY][eE][sS]|[yY]) 
            exit
            ;;
        *)
            continue
            ;;
    esac
}

confirm(){
    # call with a prompt string or use a default
    read -r -p "${1:-Are you sure? [y/N]} " response
    case "$response" in
        [yY][eE][sS]|[yY]) 
            true && $1
            ;;
        *)
            confirm_exit
            ;;
    esac
}

# Copy root ssh-key for setup 
copy_ssh_key(){
	echo "${green} Create SSH key and copy to all Server ${reset}" && sleep 2s

	# Copy hosts name
	# [ -f /root/.ssh/id_rsa.pub ] && echo "/root/.ssh/id_rsa.pub exists Yes to recreate ssh-key" &&  confirmr"
	echo -e "\n\n\n\n" | ssh-keygen -t rsa -C "Admin" -N ""
	echo
	#read -r -p "Root password on all server:" password
	echo ${HOSTS[@]}	
	for node in "${HOSTS[@]}"
	do 
		# ssh-copy-id root@node
		sshpass -p "$password" ssh-copy-id -f root@"$node"
		echo ""
		echo Key for root copied to the "$node"
		echo ""
		
		# Copy /etc/hosts file
		scp "$DIR"/conf/hosts root@"$node":/etc/hosts
		# Copy execute file ceph_node_install.sh to node
		ssh root@"$node" 'mkdir -p bash /opt/ceph-install'
		scp "$DIR"/ceph_node_install.sh root@"$node":/opt/ceph-install/
		# Create user and copy ssh-key
		ssh root@"$node" "bash /opt/ceph-install/ceph_node_install.sh create_cephuser '$CEPHUSER' '$CEPHUSER_PWD'"
		sshpass -p "$password" ssh-copy-id -f "$CEPHUSER"@"$node"
		echo 
		echo "Key for '$CEPHUSER' copied to the '$node'"
		echo 
	done
}


# Check if CEPH installed somenode
check_install(){
	echo "${green} Check_install ${reset}" && sleep 2s
	# Check Install ceph-deploy
	new_v_cdeploy="$(yum --disablerepo="*" --enablerepo="Ceph*" list available | grep ceph-deploy | awk '{print $2}')"
	now_v_cdeploy="$(ceph-deploy --version)"
	if [ "$new_v_cdeploy" != "$now_v_cdeploy" ] ; then 
		echo ceph-deploy "$now_v_cdeploy" old version or does not installed!
	else
		echo ceph-deploy "$new_v_cdeploy" already installed the last version!
	fi
	# Check Install ceph
	for node in "${HOSTS[@]}"
	do 
		ssh root@"$node" 'bash /opt/ceph-install/ceph_node_install.sh requirement' 
		ssh root@"$node" 'bash /opt/ceph-install/ceph_node_install.sh check_install_ceph' 
	done
	
	#Cleaning Previous Ceph Environment 
	# yum remove ceph ceph-radosgw libceph* librbd* librados* -y 
	#ceph-deploy purge node1 node2 node3
	#ceph-deploy purgedata node1 node2 node3
	#ceph-deploy forge
	}


config_ntpd(){
	echo "${green} Config_NTPD ${reset}" && sleep 2s
	# 
	if [ "${#NTPD[@]}" == "0" ]; then
		# echo Your CLUSTER haven't any local NTPD Server !!! Do you want continue?
		# read response
		read -r -p "${1:-Your CLUSTER havent any local NTPD Server \n !!! Do you want continue? [y/N]} " response
		case "$response" in [yY][eE][sS]|[yY]) 
			for node in "${HOSTS[@]}"
			do 
				ssh root@"$node" 'bash /opt/ceph-install/ceph_node_install.sh setup_ntpd 1'
				scp "$DIR"/conf/ntp.conf root@"$node":/etc/ntp.conf 
				ssh root@"$node" 'bash /opt/ceph-install/ceph_node_install.sh setup_ntpd 2'
			done
            		;;
        	*)
            		exit
            		;;
		esac
	else
		# Using maximum 3 NTPD Server on Cluster
		echo "Your host.csv config have cluster ${#NTPD[@]} NTPD_SERVER : ${NTPD[@]}"
		if [ "${#NTPD[@]}" -gt 3 ]; then 
			echo "We will be use maximum 3 NTPD_SERVER on cluster"
			NTPD=("${NTPD[0]}" "${NTPD[1]}" "${NTPD[2]}")
			echo "${NTPD[@]}"
		fi

		# Prepare NTPD Server config
		for i in $(seq 0 $(expr ${#NTPD[@]} - 1))
		do
			if [ "$i" -eq "0" ] ; then 
				cp "$DIR"/conf/ntp.conf "$DIR"/conf/ntp"$i".conf	
				sed -i "s|\#allow $ip_public|allow $ip_public|g" "$DIR"/conf/ntp"$i".conf	
				sed -i "s|\#logfile \/var\/log\/ntp.log|logfile \/var\/log\/ntp.log|g" "$DIR"/conf/ntp"$i".conf
			else
				cp "$DIR"/conf/ntp"$(expr $i - 1)".conf "$DIR"/conf/ntp"$i".conf
				sed -i "s|server "$(expr $i - 1)".asia.pool.ntp.org iburst|server ${NTPD[$(expr $i - 1)]} iburst|g" "$DIR"/conf/ntp"$i".conf
				sed -i "s|\#logfile \/var\/log\/ntp.log|logfile \/var\/log\/ntp.log|g" "$DIR"/conf/ntp"$i".conf
			fi
			ssh root@"${NTPD[$i]}" 'bash /opt/ceph-install/ceph_node_install.sh setup_ntpd 1'
			scp "$DIR"/conf/ntp"$i".conf root@"${NTPD[$i]}":/etc/ntp.conf
			ssh root@"${NTPD[$i]}" 'bash /opt/ceph-install/ceph_node_install.sh setup_ntpd 2'
		done


		# Prepare NTPD Client config
		cp "$DIR"/conf/ntp.conf "$DIR"/conf/ntp_client.conf

		for i in $(seq 0 $(expr ${#NTPD[@]} - 1)) #"${NTPD[@]}"
		do 
			sed -i "s|server "$i".asia.pool.ntp.org iburst|server ${NTPD[$i]} iburst|g" "$DIR"/conf/ntp_client.conf
		done
		
		for node in "${HOSTS[@]}"
		do 
			exists="$([[ ${NTPD[@]} =~ (^|[[:space:]])"$node"($|[[:space:]]) ]] && echo 'yes' || echo 'no')"
			if [ "$exists" == "no" ]; then
				ssh root@"$node" 'bash /opt/ceph-install/ceph_node_install.sh setup_ntpd 1'
				scp "$DIR"/conf/ntp_client.conf root@"$node":/etc/ntp.conf
				ssh root@"$node" 'bash /opt/ceph-install/ceph_node_install.sh setup_ntpd 2'
			fi
		done
	fi
}


chose_version(){
	echo "${green} Choise CEPH version install ${reset}" && sleep 2s
	read -r -p "${1:-Choise CEPH version 1-jewel 2-luminous:} " response
	case $response in
		1)
			# ceph-deploy install --release jewel "$(echo ${HOSTS[@]})"
			for node in "${HOSTS[@]}"
			do
				ssh root@"$node" 'rm -rf /etc/yum.repos.d/ceph.*'
				scp "$DIR"/conf/jewel.repo root@"$node":/etc/yum.repos.d/ceph.repo
			done
			echo ""
			echo Successfully add repos Ceph-jewel to all node to manual install 
			echo ""
			;;
		2)
			# ceph-deploy install --release luminous "$(echo ${HOSTS[@]})"
			for node in "${HOSTS[@]}"
			do 
				ssh root@"$node" 'rm -rf /etc/yum.repos.d/ceph.*'
				scp "$DIR"/conf/luminous.repo root@"$node":/etc/yum.repos.d/ceph.repo
			done
			echo ""
			echo Successfully add repos Ceph-jewel to all node to manual install
			echo ""
			;;
		*)
			echo "Wrong syntax !!! Please rechoise" 
			chose_version
			;;
	esac 
}


install_ceph(){
	echo "${green} Install CEPH ${reset}" && sleep 2s
	check_install
	wait
	chose_version
	# Init cluster CEPH
	if [ ! -d "$DIRECTORY" ]; then
		mkdir -p /root/ceph-deploy && cd /root/ceph-deploy
	else 
		mv /root/ceph-deploy /root/ceph-deploy-bk && mkdir -p /root/ceph-deploy && cd /root/ceph-deploy
	fi
	# mkdir -p /root/ceph-deploy && cd /root/ceph-deploy
	yum install ceph-deploy -y
	ceph-deploy new $(echo ${MON[@]})
	# Modify config 
	echo >> ceph.conf
	cat "$DIR"/conf/ceph.conf | awk '{if (NR>=10) print}' >> ceph.conf
	dos2unix ceph.conf

	for node in "${HOSTS[@]}"
	do
 			ssh root@"$node" 'bash /opt/ceph-install/ceph_node_install.sh m_cephinstall' &
	done
	wait
	
	# Init ceph cluster 
	ceph-deploy mon create-initial

	# Copy config to another hosts
	ceph-deploy admin $(echo ${HOSTS[@]})

	# Install NodeOSD
	ceph-deploy osd create $(echo ${DISK[@]})

	# Check installed 
	check_install
}


bendmark_cluster(){
	echo "${green} Bendmark_cluster ${reset}" && sleep 2s
	echo 
	echo "Temp null"
	echo 
}

install_cephdash(){
	echo "${green} Install Ceph Dash for monitor ${reset}" && sleep 2s
	yum -y install httpd mod_wsgi mod_ssl
	systemctl start httpd
	systemctl enable httpd
	cd /var/www/html
	git clone https://github.com/Crapworks/ceph-dash.git
	cp "$DIR"/conf/cephdash.conf /etc/httpd/conf.d/
	mkdir /etc/httpd/ssl/
	echo -e "\n\n\n\n\n\n\n\n" |openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout /etc/httpd/ssl/apache.key -out /etc/httpd/ssl/apache.crt
	systemctl restart httpd.service
	echo 
	echo "Monintor CEPH cluster login $(cat /etc/httpd/conf.d/cephdash.conf | grep ServerName | head -1 | awk '{print $2}')"
	echo 
}


# Main 
[ "$UID" -eq 0 ] || { echo "This script must be run as root."; exit 1;}

echo ""
echo "${red}Step1: Preinstall${reset}"
preinstall
echo "${red}End: Step1${reset}"

echo ""
echo "${red}Step2: Readfile${reset}"
readfile
echo "${red}End: Step2${reset}"

echo ""
echo "${red}Step3: Copy_ssh_key & source${reset}"
copy_ssh_key
echo "${red}End: Step3${reset}"

echo ""
echo "${red}Step4: Config NTPD ${reset}"
config_ntpd
echo "${red}End: Step4 ${reset}"

echo ""
echo "${red}Step5: Install CEPH ${reset}"
install_ceph
echo "${red}End: Step5${reset}"


echo ""
echo "${red}Step6: Bendmark_cluster${reset}"
#bendmark_cluster
echo "${red}End: Step6${reset}"

echo ""
echo "${red}Step7: Install_monitor${reset}"
install_cephdash
echo "${red}End: Step7${reset}"

# End
end=$(date +%s)
echo "${red}End Install ${reset}"
echo "Install end: Time exec is $(expr $end - $begin) "
echo "${red}End: Step7 ${reset}"
