#!/bin/sh
#./media-mux-action-batch.sh -p passwd -a [status/stop/volume]
USAGE="usage:$0 -p <passwd> -a <stop/status/volume/frozenframe> -v <value>"
PASSWD="OmJyYjB4" #default-pw: brb0x
ACTION="status"
VALUE="none"
APIPORT=8080
FINAL_RES=0
EXEC_SCRIPT=/home/pi/media-mux/media-mux-action.sh
EXEC_SCRIPT_FF=/home/pi/media-mux/media-mux-frozen-frame.sh

while getopts p:a:v: f
do
	case $f in
	p) PASSWD=$OPTARG ;;
	a) ACTION=$OPTARG ;;
	v) VALUE=$OPTARG ;;
	esac
done

if [ $# -lt 2  ]; then
	echo $USAGE
	exit 1
fi

if [ $PASSWD = "none" ]; then
	echo "Error: missing password argument"
	echo $USAGE
	exit 1
fi

#DEVICES=$(avahi-browse -ac | grep "IPv4 media-mux-" | awk '{print $4}')
DEVICES=$(avahi-browse -arc 2>/dev/null | grep -A2 "IPv4 media-mux" | grep address | sort -u |sed 's/   address = \[//'|sed 's/\]//')
for i in $DEVICES
do
	if [ $ACTION = "frozenframe" ]; then
		$EXEC_SCRIPT_FF -i $i -p $PASSWD
	else
		$EXEC_SCRIPT -i $i -p $PASSWD -a $ACTION -v $VALUE
	fi
	[ $? != "0" ] && FINAL_RES=1
done

exit $FINAL_RES
