#!/bin/sh
#this script is used for publishing json data on a configured  topic through linux-domain-socket of aws-iot-pubsub-agent

PUBSUBCLIENT=aws-iot-pubsub-client
USAGE="usage: $0 <KEY_CODE> [KEY_BTN_ON/KEY_BTN_OFF/KEY_MUTE/KEY_VOLUMEUP/KEY_VOLUMEDOWN/KEY_PREVIOUSSONG/KEY_NEXTSONG/KEY_PLAYPAUSE]"

if [ -z $1 ]; then
	echo $USAGE 
	return 1
fi

publish_message() #$1=topic $2=msg
{
	TOPIC=$(uci get $1 2>/dev/null)
	MSG=$(uci get $2 2>/dev/null)
	if [ ! -z $TOPIC ]; then
		$PUBSUBCLIENT -t "$TOPIC" -s "$MSG"
	else
		echo "property not found: $2"
	fi
}

case "$1" in
	#"KEY_BTN_ON")
	#	publish_message awsiot-events.Settings.KEY_BTN_ON_topic awsiot-events.Settings.KEY_BTN_ON_message	
	#	;;
	#"KEY_BTN_OFF")
	#	publish_message awsiot-events.Settings.KEY_BTN_OFF_topic awsiot-events.Settings.KEY_BTN_OFF_message	
	#	;;
	"KEY_MUTE")
		#publish_message awsiot-events.Settings.KEY_MUTE_topic awsiot-events.Settings.KEY_MUTE_message	
		media-mux-action-batch.sh -p OmJyYjB4 -a stop
		;;
	"KEY_VOLUMEUP")
		#publish_message awsiot-events.Settings.KEY_VOLUMEUP_topic awsiot-events.Settings.KEY_VOLUMEUP_message	
		media-mux-action-batch.sh -p OmJyYjB4 -a volumeup
		;;
	"KEY_VOLUMEDOWN")
		#publish_message awsiot-events.Settings.KEY_VOLUMEDOWN_topic awsiot-events.Settings.KEY_VOLUMEDOWN_message	
		media-mux-action-batch.sh -p OmJyYjB4 -a volumedn
		;;
	"KEY_PREVIOUSSONG")
		#publish_message awsiot-events.Settings.KEY_PREVIOUSSONG_topic awsiot-events.Settings.KEY_PREVIOUSSONG_message	
		media-mux-play-batch.sh -p OmJyYjB4 -u udp://@239.255.42.61:5004	
		;;
	"KEY_NEXTSONG")
		#publish_message awsiot-events.Settings.KEY_NEXTSONG_topic awsiot-events.Settings.KEY_NEXTSONG_message	
		media-mux-play-batch.sh -p OmJyYjB4 -u udp://@239.255.42.64:5004	
		;;
	"KEY_PLAYPAUSE")
		#publish_message awsiot-events.Settings.KEY_PLAYPAUSE_topic 1awsiot-events.Settings.KEY_PLAYPAUSE_message	
		media-mux-play-batch.sh -p OmJyYjB4 -u udp://@239.255.42.62:5004	
		;;
	*)
		if [ -z $1 ]; then
			echo $USAGE 
			return 1
		fi
		;;
esac

return 0
