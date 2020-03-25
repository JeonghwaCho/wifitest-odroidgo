#!/bin/bash

# draft version of OGA wifi test

### set basic information
BOARD_NO=1
HOSTIP=192.168.0.180
LOG_FILE=log
AP_SSID="AP1"
AP_PW="AP1_password"

function set_connection {
	echo "----- set connection"
	nmcli radio wifi on
	nmcli dev wifi con ${AP_SSID} password ${AP_PW}
}

function valid_ip {
	local  ip=$1
	local  stat=1

	if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
		OIFS=$IFS
		IFS='.'
		ip=($ip)
		IFS=$OIFS
		[[ ${ip[0]} -le 255 && ${ip[1]} -le 255 \
			&& ${ip[2]} -le 255 && ${ip[3]} -le 255 ]]
		stat=$?
	fi

	return $stat
}

function check_connection {
	echo "----- start check connection"

	### Check ip address
	ipaddr=`ip addr show wlan0 2>/dev/null|awk '/inet / {print $2}'|cut -f1 -d"/"`
	echo "ipaddr $ipaddr"

	if [ -z "$ipaddr" ]; then
		echo "no valid ipaddr, check network"
		echo "no valid ipaddr, FAIL" > fail.log
		exit 1
	fi

	### check ip validation
	if valid_ip $ipaddr; then
		echo "valid ip address"
	else
		echo "invalid ip, check network"
		echo "invalid ip, check network" > fail.log
	fi

	### Check wifi channel
	cur_ch=`iwlist wlan0 channel | grep Frequency|awk '{print $5}'|cut -f1 -d")"`
	if [ -z $cur_ch ]; then
		echo "wifi channel fail, check network"
		echo "wifi channel fail, check network" > fail.log
		exit 1
	fi

	### Create log file
	LOG_FILE=board${BOARD_NO}-CH${cur_ch}.log
	touch $LOG_FILE

	### Write connection info and date
	timedatectl set-timezone Asia/Seoul
	echo "$(date --iso-8601=seconds)" >> $LOG_FILE 

	echo "----- check connection -----" >> $LOG_FILE
	echo "BOARD ${BOARD_NO} / WIFI CH $cur_ch" >> $LOG_FILE
}

function run_iperf3 {
	echo "----- start iperf3"
	echo "----- iperf3 -----" >> $LOG_FILE
	iperf_tx=`iperf3 -c ${HOSTIP} -t 10 -P 10 | grep 'sender' | grep SUM | awk '{print $6}'`
	if [ -z "$iperf_tx" ]; then
		echo "Check iperf server daemon of Host"
		echo "Check iperf server daemon of Host" >> $LOG_FILE
		return 0;
	fi
	iperf_rx=`iperf3 -c ${HOSTIP} -t 10 -P 10 | grep 'receiver' | grep SUM | awk '{print $6}'`

	printf 'iperf tx/rx (Mbits/sec)\n%s\n%s\n' "$iperf_tx" "$iperf_rx" >> $LOG_FILE
}

function check_rssi {
	echo "----- start rssi"
	echo "----- rssi -----" >> $LOG_FILE
	echo "TIME (s), SIGNAL STRENGTH (dBm)" >> $LOG_FILE

	for ((i=0; i<=10; i=i+2)); do
		iw dev wlan0 station dump | awk -vt=$i '$1=="signal:"{s=$2} END {printf "%d,%d\n", t, s}' >> $LOG_FILE
		sleep 2 
	done
}

function check_smb {
	smbdir="/mnt/smbclone"
	clientdir="/home/odroid"
	programdir="/home/odroid/wifitest"
	imgname="rand_100M.bin"

	echo "----- start samba copy test"
	echo "----- samba copy test -----" >> $LOG_FILE

	### check samba directory
	if [ ! -e $smbdir ]; then
	        echo "no smbdir, now create it"
	        mkdir -p $smbdir
	fi

	### mount && check file
	### Host directory : /mnt/smbhost
	mount -t cifs -o username=odroid,password=odroid //${HOSTIP}/smbhost $smbdir
	if [ ! -e $smbdir/$imgname ]; then
	        echo "no target file, samba mount FAIL!"
	        return 0
	fi
	echo "mount done!"

	### copy target file from host (C2) to client (OGA)
	echo "copy start"
	sync
	{ time cp $smbdir/$imgname $clientdir; } 2>> $LOG_FILE
	echo "copy done"

	### checksum compare
	hash_ref=`cat $programdir/${imgname}.md5sum | cut -b -32`
	hash_img=`md5sum $clientdir/$imgname | cut -b -32`
	echo "hash : $hash_ref / $hash_img"

	if [ "$hash_ref" = "$hash_img" ]; then
		echo "checksum ok"
	else
		echo "checksum fail"
		echo "########### SMB TEST : CHECKSUM FAIL!" >> $LOG_FILE
	fi

	rm $clientdir/$imgname

	### umount
	umount $smbdir
	echo "samba test done"
}

echo "[ OGA ESP8266 WIFI TEST ]"

echo performance > /sys/devices/system/cpu/cpufreq/policy0/scaling_governor

check_connection

run_iperf3

check_rssi

check_smb

echo "[ TEST Done ]"
