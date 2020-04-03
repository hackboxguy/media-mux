#!/bin/sh
#./media-mux-action.sh -i 192.168.8.5 -p passwd -u udp://@239.255.42.64:5004 
USAGE="usage:$0 -i <ipaddr/hostname> -p <passwd> -u <url>"
IPADDR="127.0.0.1"
PASSWD="OmJyYjB4" #default-pw: brb0x
URL="none"
APIPORT=8080

while getopts i:p:u: f
do
	case $f in
	i) IPADDR=$OPTARG ;;
	p) PASSWD=$OPTARG ;;
	u) URL=$OPTARG ;;
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

if [ $URL = "none" ]; then
        echo "Error: missing URL argument"
        echo $USAGE
        exit 1
fi
IP=$(printf "%-15s" $IPADDR)
RES=$(curl -s -G -H "Authorization: Basic $PASSWD" "http://$IPADDR:$APIPORT/requests/status.xml?command=in_play&input=$URL")
[ $? != "0" ] && echo "$IP:Error: action failed! unable play url (check if password/url is correct)" && exit 1

exit 0