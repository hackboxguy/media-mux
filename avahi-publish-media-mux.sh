#!/bin/sh
MY_ID_STRING="media-mux-0001"
MY_ID_PORT=80
MY_ID_SERVICE="_http._tcp"
MY_ID_HW=$(ifconfig |grep -A1 eth0 |grep inet | awk '{print $2}')
avahi-publish-service -s "$MY_ID_STRING [$MY_ID_HW]" $MY_ID_SERVICE $MY_ID_PORT
