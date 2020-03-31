#!/bin/sh
#./setup.sh -t master
USAGE="usage:$0 -t <setup_type[master/slave]> -n <slave_number>"
TYPE="none"
SLAVE_NUM="none"

while getopts t:n: f
do
	case $f in
	t) TYPE=$OPTARG ;;
	n) SLAVE_NUM=$OPTARG ;;
	esac
done


if [ $# -lt 2  ]; then
	echo $USAGE
	exit 1
fi

if [ $TYPE = "none" ]; then
	echo "Error: missing type argument [master/slave]"
	echo $USAGE
	exit 1
fi

if [ $TYPE = "master" ]; then
	ln -s media-mux-autoplay-master.sh media-mux-autoplay.sh
	echo "media-mux-0001" > /etc/hostname
	cp rc.local to /etc/
elif [ $TYPE = "slave" ]; then
	if [ $SLAVE_NUM = "none" ]; then
		echo "Error: missing slave-number -n argument"
		echo $USAGE
		exit 1
	else
		ln -s media-mux-autoplay-slave.sh media-mux-autoplay.sh
		echo "media-mux-$SLAVE_NUM" > /etc/hostname #TODO format the number to %000X
		cp rc.local to /etc/
	fi
else
	echo "Error: invalid type argument $TYPE"
	echo $USAGE
	exit 1
fi
echo "Setup complete successfully, please reboot the board"

#todo
#1)apt-get install avahi
#2)enable avahi announcement