#!/bin/sh
#./media-mux-action-batch.sh -p passwd -u udp://@239.255.42.64:5004 
USAGE="usage:$0 -p <passwd> -u <url>"
PASSWD="OmJyYjB4" #default-pw: brb0x
URL="none"
APIPORT=8080
FINAL_RES=0
EXEC_SCRIPT=media-mux-play.sh

while getopts p:u: f
do
	case $f in
	p) PASSWD=$OPTARG ;;
	u) URL=$OPTARG ;;
	esac
done

if [ $# -lt 2  ]; then
	echo $USAGE
	exit 1
fi

if [ $URL = "none" ]; then
        echo "Error: missing URL argument"
        echo $USAGE
        exit 1
fi
[ ! -f "/usr/bin/$EXEC_SCRIPT" ] && EXEC_SCRIPT=/home/pi/media-mux/$EXEC_SCRIPT

DEVICES=$(avahi-browse -art 2>/dev/null | grep -A2 "IPv4 media-mux" | grep address | sort -u |sed 's/   address = \[//'|sed 's/\]//')

for i in $DEVICES
do
	[ $i = "127.0.0.1" ] && continue
	$EXEC_SCRIPT -i $i -p $PASSWD -u $URL
	[ $? != "0" ] && FINAL_RES=1
done

exit $FINAL_RES
