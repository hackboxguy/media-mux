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

if [ $NUM = "0001" ]; then
	ln -s media-mux-autoplay-master.sh media-mux-autoplay.sh
else
	ln -s media-mux-autoplay-slave.sh media-mux-autoplay.sh
fi

#install dependencies
sudo apt-get -y install avahi-daemon avahi-discover libnss-mdns avahi-utils #isc-dhcp-server curl

#prepare avahi publish 
sed -i "s/media-mux-\(.*\)/media-mux-$NUM\"/g" avahi-publish-media-mux.sh

#set hostname
echo "media-mux-$NUM" > /etc/hostname

#setup auto startup script
cp rc.local to /etc/

#for master, prepare dhcp server
#if [ $NUM = "0001" ]; then
#	sudo apt-get -y install isc-dhcp-server
#	cp dhcpd.conf /etc/dhcp/
#fi

echo "Setup completed successfully, please reboot the board"
