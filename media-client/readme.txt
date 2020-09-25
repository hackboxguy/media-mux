media-client is a utility(daemon) that plays configured media files upen button press(keyboard or joystick-buttons).
which file to play on a button press is configured in a .json file as key-value pair.
upon button press, media-client sends an http command to vlc player for playing a locally stored file.

by default, media-client looks for the config file at: /media/pi/MediaFiles/button-map.json , if not found, then stops

how to compile this utility?
g++ media-client.cpp -o media-client

