#!/bin/sh
#for touchscreen based display let user manually start the media-mux-player
/home/pi/media-mux/media-mux-play.sh -i 127.0.0.1 -u udp://@239.255.42.65:5004
#/home/pi/media-mux/media-mux-play.sh -i 127.0.0.1 -u rtsp://media-mux-0001:8554/test-stream-1?vlcmulticast
