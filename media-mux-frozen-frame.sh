#!/bin/sh
#./media-mux-frozen-frame.sh -p passwd -i ipaddr
USAGE="usage:$0 -p <passwd> -i <ip>"
PASSWD="OmJyYjB4" #default-pw: brb0x
IPADDR="127.0.0.1"
EXEC_SCRIPT=/home/pi/media-mux/media-mux-action.sh

while getopts p:i:h f
do
	case $f in
	p) PASSWD=$OPTARG ;;
	i) IPADDR=$OPTARG ;;
	h) echo $USAGE;exit 1 ;;
	esac
done

IP=$(printf "%-15s" $IPADDR)
VAL1=$($EXEC_SCRIPT -i $IPADDR -p $PASSWD -a custom -v decodedvideo)
sleep 0.5
VAL2=$($EXEC_SCRIPT -i $IPADDR -p $PASSWD -a custom -v decodedvideo)
if [ "$VAL1" = "$VAL2" ]; then
	echo "$IP:Error: Frozen-Frame!!!" #decodevideo count doesnt increase when vlc media-playback has frozen frame.
	exit 1
else
	echo "$IP:OK: No frozen-Frame"
	exit 0
fi
