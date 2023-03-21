#!/bin/sh
#./media-mux-action-batch.sh -p passwd -a [status/stop/volume/volumeup/volumedn/frozenframe]
USAGE="usage:$0 -p <passwd> -a <stop/status/volume/volumeup/volumedn/frozenframe> -v <value>"
PASSWD="OmJyYjB4" #default-pw: brb0x
ACTION="status"
VALUE="none"
APIPORT=8080
FINAL_RES=0
EXEC_SCRIPT=media-mux-action.sh
EXEC_SCRIPT_FF=media-mux-frozen-frame.sh
EXEC_SCRIPT_VOL=media-mux-volume.sh

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

[ ! -f "/usr/bin/$EXEC_SCRIPT" ] && EXEC_SCRIPT=/home/pi/media-mux/$EXEC_SCRIPT
[ ! -f "/usr/bin/$EXEC_SCRIPT_FF" ] && EXEC_SCRIPT_FF=/home/pi/media-mux/$EXEC_SCRIPT_FF
[ ! -f "/usr/bin/$EXEC_SCRIPT_VOL" ] && EXEC_SCRIPT_VOL=/home/pi/media-mux/$EXEC_SCRIPT_VOL

DEVICES=$(avahi-browse -art 2>/dev/null | grep -A2 "IPv4 media-mux" | grep address | sort -u |sed 's/   address = \[//'|sed 's/\]//')
for i in $DEVICES
do
	[ $i = "127.0.0.1" ] && continue
	if [ $ACTION = "frozenframe" ]; then
		$EXEC_SCRIPT_FF -i $i -p $PASSWD
	elif [ $ACTION = "volumeup" ]; then
		$EXEC_SCRIPT_VOL -i $i -p $PASSWD -a u #volume-up
	elif [ $ACTION = "volumedn" ]; then
		$EXEC_SCRIPT_VOL -i $i -p $PASSWD -a d #volume-down
	else
		$EXEC_SCRIPT -i $i -p $PASSWD -a $ACTION -v $VALUE
	fi
	[ $? != "0" ] && FINAL_RES=1
done

exit $FINAL_RES
