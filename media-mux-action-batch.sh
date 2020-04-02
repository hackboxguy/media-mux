#!/bin/sh
#./media-mux-action-batch.sh -p passwd -a [status/stop/volume]
USAGE="usage:$0 -p <passwd> -a <stop/status/volume> -v <volume_value>"
PASSWD="OmJyYjB4" #default-pw: brb0x
ACTION="status"
VALUE="none"
APIPORT=8080
FINAL_RES=0

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

DEVICES=$(avahi-browse -arc 2>/dev/null | grep -A2 "IPv4 media-mux" | grep address | sort -u |sed 's/   address = \[//'|sed 's/\]//')
for i in $DEVICES
do
	./media-mux-action.sh -i $i -p $PASSWD -a $ACTION -v $VALUE
	[ $? != "0" ] && FINAL_RES=1
done

exit $FINAL_RES