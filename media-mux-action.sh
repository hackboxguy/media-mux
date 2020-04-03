#!/bin/sh
#./media-mux-action.sh -i 192.168.8.5 -p passwd -a [status/stop]
USAGE="usage:$0 -i <ipaddr/hostname> -p <passwd> -a <stop/status/volume> -v <volume_value>"
IPADDR="127.0.0.1"
PASSWD="OmJyYjB4" #default-pw: brb0x
ACTION="status"
VALUE="none"
APIPORT=8080
while getopts i:p:a:v: f
do
	case $f in
	i) IPADDR=$OPTARG ;;
	p) PASSWD=$OPTARG ;;
	a) ACTION=$OPTARG ;;
	v) VALUE=$OPTARG ;;
	esac
done

if [ $# -lt 2  ]; then
	echo $USAGE
	exit 1
fi

#echo "IPADDR=$IPADDR";echo "PASSWD=$PASSWD";echo "ACTION=$ACTION"

if [ $PASSWD = "none" ]; then
	echo "Error: missing password argument"
	echo $USAGE
	exit 1
fi
IP=$(printf "%-15s" $IPADDR)
if [ $ACTION = "status" ]; then
	RES=$(curl -s -G -H "Authorization: Basic $PASSWD" "http://$IPADDR:$APIPORT/requests/status.xml" | grep state)
	[ $? != "0" ] && echo "$IP:Error: action failed! unable to read player status (check if password is correct)" && exit 1
	if [ $RES = "<state>stopped</state>" ]; then
		echo "$IP:Player-state: Stopped"	
		elif [ $RES = "<state>stopped</state><information>" ]; then
		echo "$IP:Player-state: Stopped"	
        elif [ $RES = "<state>playing</state>" ]; then
		echo "$IP:Player-state: Playing"	
		elif [ $RES = "<state>playing</state><information>" ]; then
		echo "$IP:Player-state: Playing"	
	else
		echo "$IP:Player-state: $RES"
	fi
elif [ $ACTION = "volume" ]; then
	if [ $VALUE = "none" ]; then
		RES=$(curl -s -G -H "Authorization: Basic $PASSWD" "http://$IPADDR:$APIPORT/requests/status.xml" | grep volume)
		[ $? != "0" ] && echo "$IP:Error: action failed! unable to read volume (check if password is correct)" && exit 1
		echo "$IP:$RES"	
	else
		RES=$(curl -s -G -H "Authorization: Basic $PASSWD" "http://$IPADDR:$APIPORT/requests/status.xml" --data-urlencode "command=volume" --data-urlencode "val=$VALUE")
		[ $? != "0" ] && echo "$IP:Error: action failed! unable set volume (check if password/volume-value is correct)" && exit 1
	fi
elif [ $ACTION = "stop" ]; then
	RES=$(curl -s -G -H "Authorization: Basic $PASSWD" "http://$IPADDR:$APIPORT/requests/status.xml?command=pl_stop")
	[ $? != "0" ] && echo "$IP:Error: action failed! unable to stop player (check if password is correct)" && exit 1
else
	echo "$IP:Error: invalid action argument ==> $ACTION"
	echo $USAGE
	exit 1
fi

exit 0