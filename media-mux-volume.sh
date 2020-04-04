#!/bin/sh
#./media-mux-volume.sh -p passwd -i ipaddr -a [u/d]
USAGE="usage:$0 -p <passwd> -i <ip> -a <u/d>"
PASSWD="OmJyYjB4" #default-pw: brb0x
IPADDR="127.0.0.1"
EXEC_SCRIPT=/home/pi/media-mux/media-mux-action.sh
ACTION="none"

while getopts p:i:a:h f
do
	case $f in
	p) PASSWD=$OPTARG ;;
	i) IPADDR=$OPTARG ;;
	a) ACTION=$OPTARG ;;
	h) echo $USAGE;exit 1 ;;
	esac
done

if [ $ACTION = "none" ]; then
	echo "Error: missing action argument [u/d]"
	echo $USAGE
	exit 1
fi

IP=$(printf "%-15s" $IPADDR)
VAL1=$($EXEC_SCRIPT -i $IPADDR -p $PASSWD -a volume)
[ $? != "0" ] && echo "$IP:Error: action failed! unable to read current volume setting(check if password is correct)" && exit 1
NEW_VOLUME=$(echo $VAL1 | awk '{print $2}' | sed 's/:<volume>//'| sed 's/<\/volume>//' | sed 's/<information>//')

if [ $ACTION = "u" ]; then
	NEW_VOLUME=$(( NEW_VOLUME + 20 ))
else
	NEW_VOLUME=$(( NEW_VOLUME - 20 ))
fi

VAL2=$($EXEC_SCRIPT -i $IPADDR -p $PASSWD -a volume -v $NEW_VOLUME)
[ $? != "0" ] && echo "$IP:Error: action failed! unable to set player volume (check if password is correct)" && exit 1

exit 0
