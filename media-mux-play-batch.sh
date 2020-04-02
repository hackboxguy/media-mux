#!/bin/sh
#./media-mux-action-batch.sh -p passwd -u udp://@239.255.42.64:5004 
USAGE="usage:$0 -p <passwd> -u <url>"
PASSWD="OmJyYjB4" #default-pw: brb0x
URL="none"
APIPORT=8080
FINAL_RES=0

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

DEVICES=$(avahi-browse -arc 2>/dev/null | grep -A2 "IPv4 media-mux" | grep address | sort -u |sed 's/   address = \[//'|sed 's/\]//')

for i in $DEVICES
do
	./media-mux-play.sh -i $i -p $PASSWD -u $URL
	[ $? != "0" ] && FINAL_RES=1
	#RES=$(curl -s -G -H "Authorization: Basic $PASSWD" "http://$i:$APIPORT/requests/status.xml?command=in_play&input=$URL")
	#[ $? != "0" ] && echo "Error: action failed! unable play url at ip $i (check if password/url is correct)" && FINAL_RES=1
done

exit $FINAL_RES