#!/bin/sh
#./setup.sh -n 1 
USAGE="usage:$0 -n <pi_sequence_number> (1 is for master-raspi, remaining numbers are for slave-raspi)"
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
rm -rf media-mux-autoplay.sh >/dev/null #remove any existing solft-link
if [ $NUM = "0001" ]; then
	ln -s media-mux-autoplay-master.sh media-mux-autoplay.sh
else
	ln -s media-mux-autoplay-slave.sh media-mux-autoplay.sh
fi
test 0 -eq $? && echo "[OK]" || echo "[FAIL]"


#install dependencies
printf "Installing dependencies ................................ "
DEBIAN_FRONTEND=noninteractive apt-get install -qq avahi-daemon avahi-discover libnss-mdns avahi-utils kodi jq nodejs npm < /dev/null > /dev/null
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


#printf "Enabling ssh server .................................... "
#systemctl enable ssh 1>/dev/null 2>/dev/null
#systemctl start ssh 1>/dev/null 2>/dev/null
#test 0 -eq $? && echo "[OK]" || echo "[FAIL]"


#printf "Forcing audio output to analog-out ..................... "
#amixer cset numid=3 1 > /dev/null #0-automatic 1-analog 2-hdmi
#test 0 -eq $? && echo "[OK]" || echo "[FAIL]"

printf "Compiling media-mux-controller-server................... "
gcc media-mux-controller.c -o media-mux-controller 1>/dev/null 2>/dev/null
test 0 -eq $? && echo "[OK]" || echo "[FAIL]"

#for master, enable dhcp server and mediamtx service
if [ $NUM = "0001" ]; then
	#	sudo apt-get -y install isc-dhcp-server
	#	cp dhcpd.conf /etc/dhcp/
	printf "Enabling mediamtx service............................... "
	#systemctl enable /home/pi/media-mux/mediamtx.service 1>/dev/null 2>/dev/null
	#systemctl start mediamtx.service 1>/dev/null 2>/dev/null
	test 0 -eq $? && echo "[OK]" || echo "[FAIL]"
fi

#useful for raspi-4 with touchscreen based display
printf "Preparing Kodi-config and desktop shortcuts............. "
runuser -l pi -c 'mkdir -p /home/pi/.kodi/userdata'
runuser -l pi -c 'cp /home/pi/media-mux/sources.xml /home/pi/.kodi/userdata/'
runuser -l pi -c 'cp /home/pi/media-mux/guisettings.xml /home/pi/.kodi/userdata/'
runuser -l pi -c 'cp /home/pi/media-mux/wf-panel-pi.ini /home/pi/.config/'
runuser -l pi -c 'cd /home/pi/media-mux/kodisync;npm install'
#cp mediamuxstart.png /usr/share/pixmaps/
#cp mediamuxstop.png /usr/share/pixmaps/
#cp mediamuxstart.png /usr/share/icons/hicolor/48x48/apps/
#cp mediamuxstop.png /usr/share/icons/hicolor/48x48/apps/
#cp mediamuxstart.desktop /usr/share/applications/
#cp mediamuxstop.desktop /usr/share/applications/
test 0 -eq $? && echo "[OK]" || echo "[FAIL]"

sync

echo   "Setup completed successfully! Reboot the board ......... "
