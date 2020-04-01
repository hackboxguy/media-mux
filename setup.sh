#!/bin/sh
#./setup.sh -n 1 
USAGE="usage:$0 -n <pi_sequence_number> (1 is for master-master, remaining numbers are for slave-raspi)"
SLAVE_NUM="none"

while getopts n: f
do
	case $f in
	#t) TYPE=$OPTARG ;;
	n) SLAVE_NUM=$OPTARG ;;
	esac
done

if [ $# -lt 2  ]; then
	echo $USAGE
	exit 1
fi

if [ $(id -u) -ne 0 ]; then
	echo "Please run setup as root ==> sudo ./setup.sh -n $SLAVE_NUM"
	exit
fi

case $SLAVE_NUM in
    ''|*[!0-9]*)
		echo "Error: $SLAVE_NUM is not a number" && exit 1 ;;
    *) 
		NUM=$(printf "%04d" $SLAVE_NUM) ;;
esac

printf "Installing auto-startup-player ......................... "
if [ $NUM = "0001" ]; then
	ln -s media-mux-autoplay-master.sh media-mux-autoplay.sh
else
	ln -s media-mux-autoplay-slave.sh media-mux-autoplay.sh
fi
test 0 -eq $? && echo "[OK]" || echo "[FAIL]"


#install dependencies
printf "Installing dependencies ................................ "
DEBIAN_FRONTEND=noninteractive apt-get install -qq avahi-daemon avahi-discover libnss-mdns avahi-utils #isc-dhcp-server curl
test 0 -eq $? && echo "[OK]" || echo "[FAIL]"


#prepare avahi publish 
printf "Preparing for avahi-publish ............................ "
sed -i "s/media-mux-\(.*\)/media-mux-$NUM\"/g" avahi-publish-media-mux.sh
test 0 -eq $? && echo "[OK]" || echo "[FAIL]"


#set hostname
printf "Setting hostname ....................................... "
echo "media-mux-$NUM" > /etc/hostname
test 0 -eq $? && echo "[OK]" || echo "[FAIL]"


#setup auto startup script
printf "Customizing rc.local ................................... "
cp rc.local /etc/
test 0 -eq $? && echo "[OK]" || echo "[FAIL]"

#for master, prepare dhcp server
#if [ $NUM = "0001" ]; then
#	sudo apt-get -y install isc-dhcp-server
#	cp dhcpd.conf /etc/dhcp/
#fi

echo   "Setup completed successfully! Reboot the board ......... "