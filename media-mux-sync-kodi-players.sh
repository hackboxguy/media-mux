#!/bin/sh

#This script is used for synchronizing all the kodi-players in the network(media-mux-*) using kodisync nodejs script(https://github.com/tremby/kodisync)
#./media-mux-sync-kodi-players.sh
USAGE="usage:$0"
FINAL_RES=0

#get what is currently being played on master-kodi player
TITLE=$(curl -s -X POST -H "content-type:application/json" http://media-mux-0001:8888/jsonrpc -d '{"jsonrpc": "2.0", "method": "Player.GetItem", "params": { "properties": ["title", "album",  "duration", "file"], "playerid": 1 }, "id": "VideoGetItem"}' | jq -r .result.item.file)
if [ -z "${TITLE}" ]; then
	exit 0 #echo "Nothing is playing on kodi player of media-mux-0001!!!"
fi

#get current progress on master-kodi player
PERCENTAGE=$(curl -s -X POST -H "content-type:application/json" http://127.0.0.1:8888/jsonrpc -d '{"jsonrpc": "2.0", "method": "Player.GetProperties", "params": { "playerid": 1,"properties":["percentage"] }, "id": 1}' | jq .result.percentage)
#echo $PERCENTAGE

#stop all player(we already remember TITLE/PERCENTAGE of mater-kodi-player)
DEVICES=$(avahi-browse -art 2>/dev/null | grep -A2 "IPv4 media-mux" | grep address | sort -u |sed 's/   address = \[//'|sed 's/\]//')
for i in $DEVICES
do
	[ $i = "127.0.0.1" ] && continue
	RESP=$(curl -s -X POST -H "content-type:application/json" http://$i:8888/jsonrpc -d '{"jsonrpc": "2.0", "id":"1","method":"Player.Stop","params":{"playerid": 1}}')
done

#using avahi, discover all media-mux-* devices on the network and trigger them to play the same title of master-kodi-player
TMP_DEVICES=""
DEVICES=$(avahi-browse -art 2>/dev/null | grep -A2 "IPv4 media-mux" | grep address | sort -u |sed 's/   address = \[//'|sed 's/\]//')
for i in $DEVICES
do
	[ $i = "127.0.0.1" ] && continue
	RESP=$(curl -s -X POST -H "content-type:application/json" http://$i:8888/jsonrpc -d '{"jsonrpc": "2.0", "id":"1","method":"Player.Open","params":{"item":{"file":"'"$TITLE"'"}}}')
	TMP_DEVICES="$TMP_DEVICES $i:8888"
done

sleep 3

#using kodisync, pause all kod-players on the network exactly at same location
#echo $TMP_DEVICES
node /home/pi/media-mux/kodisync/kodisync.js $TMP_DEVICES #pause all players exactly at same location
sleep 2

#seek all players to the position of master-kodi-player
for i in $DEVICES
do
	[ $i = "127.0.0.1" ] && continue
	RESP=$(curl -s -X POST -H "content-type:application/json" http://$i:8888/jsonrpc -d '{"jsonrpc": "2.0", "id":"1","method":"Player.Seek","params":{"playerid": 1,"value":{ "percentage":'"$PERCENTAGE"'}}}')
done
sleep 2

#trigger start-playing on all kodi-players
for i in $DEVICES
do
	[ $i = "127.0.0.1" ] && continue
	RESP=$(curl -s -X POST -H "content-type:application/json" http://$i:8888/jsonrpc -d '{"jsonrpc": "2.0", "method": "Player.PlayPause", "params": { "playerid": 1 }, "id": 1}')
done

exit $FINAL_RES
