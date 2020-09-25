//gcc joystick.c -o joystick
//./joystick /dev/input/js0

/**
 * Original Author: Jason White
 *
 * Description:
 * Reads joystick/gamepad events and triggers configured commands.
 *
 * Compile:
 * g++ media-client.cpp -o media-client
 *
 * Run:
 * ./media-client [/dev/input/jsX]
 *
 * See also:
 * https://www.kernel.org/doc/Documentation/input/joystick-api.txt
 */
#include <fcntl.h>
#include <stdio.h>
#include <unistd.h>
#include <linux/joystick.h>
#include "json.hpp"
#include <iostream>
#include <fstream>
#include <string>
static const std::string default_config_file = "/media/pi/MediaFiles/button-map.json";
static const std::string player_command = "/home/pi/media-mux/media-mux-play.sh -u file:///media//pi//MediaFiles//";
/*****************************************************************************/
/**
 * Reads a joystick event from the joystick device.
 *
 * Returns 0 on success. Otherwise -1 is returned.
 */
int read_event(int fd, struct js_event *event)
{
    ssize_t bytes;

    bytes = read(fd, event, sizeof(*event));

    if (bytes == sizeof(*event))
        return 0;

    /* Error, could not read full event. */
    return -1;
}
/*****************************************************************************/
/**
 * Returns the number of axes on the controller or 0 if an error occurs.
 */
size_t get_axis_count(int fd)
{
    __u8 axes;

    if (ioctl(fd, JSIOCGAXES, &axes) == -1)
        return 0;

    return axes;
}
/*****************************************************************************/
/**
 * Returns the number of buttons on the controller or 0 if an error occurs.
 */
size_t get_button_count(int fd)
{
    __u8 buttons;
    if (ioctl(fd, JSIOCGBUTTONS, &buttons) == -1)
        return 0;

    return buttons;
}
/*****************************************************************************/
/**
 * Current state of an axis.
 */
struct axis_state {
    short x, y;
};
/**
 * Keeps track of the current axis state.
 *
 * NOTE: This function assumes that axes are numbered starting from 0, and that
 * the X axis is an even number, and the Y axis is an odd number. However, this
 * is usually a safe assumption.
 *
 * Returns the axis that the event indicated.
 */
size_t get_axis_state(struct js_event *event, struct axis_state axes[3])
{
	size_t axis = event->number / 2;

	if (axis < 3)
	{
		if (event->number % 2 == 0)
			axes[axis].x = event->value;
		else
			axes[axis].y = event->value;
	}
	return axis;
}
/*****************************************************************************/
int process_button_release(int button,const nlohmann::json &playerConfig)
{
	//this function is called with args button-number and json-config-file
	//json config file contains key-value pair that says which file to play on a specific button press.
	char tmp[255];
	//printf("button %d released\n",button);
	for (auto iter = playerConfig.begin(); iter != playerConfig.end(); ++iter)
	{
		sprintf(tmp,"BTN_%d",button);
		std::string btn(tmp);
		if(iter.key() == btn)
		{
			//system("/home/pi/media-mux/media-mux-play.sh -u file:///media//pi//MediaFiles/somefile.mp4");
			std::string media_file=iter.value();			
			std::string play_cmd = player_command + media_file;
			system(play_cmd.c_str());
			break;			
		}
	}
	return 0;
}
/*****************************************************************************/
int parse_config_file(std::string configFile,nlohmann::json &playerConfig)
{
	std::ifstream ifs;  // Not configured to throw exceptions
	ifs.open(configFile, std::ifstream::in);
	if (!ifs.is_open()) //unable to open file
	{
		printf("unable to open %s\n",configFile.c_str());
		return -1;
	}
	try 
	{
		// Parse Stream
		playerConfig = nlohmann::json::parse(ifs, nullptr, true);
		ifs.close();
		return 0;
	}
	catch (const nlohmann::json::parse_error &e1)
	{
		ifs.close();
		printf("json syntax error in %s\n",configFile.c_str());
		return -1;
	}
	return 0;
}
/*****************************************************************************/
int main(int argc, char *argv[])
{
	bool config_file_ready=false;
	nlohmann::json playerConfig;
	std::string configFile = default_config_file;
	const char *device;
	int js;
	struct js_event event;
	struct axis_state axes[3] = {0};
	size_t axis;
	if(parse_config_file(configFile,playerConfig)==0)
		config_file_ready=true;
	if (argc > 1)
		device = argv[1];
	else
		device = "/dev/input/js0";

	js = open(device, O_RDONLY);

	if (js == -1)
		perror("Could not open joystick");

	/* This loop will exit if the controller is unplugged. */
	while (read_event(js, &event) == 0)
	{
		switch (event.type)
		{
			case JS_EVENT_BUTTON:
				//printf("Button %u %s\n", event.number, event.value ? "pressed" : "released");
				if(!event.value)
				{
					if(config_file_ready==false)
					{					
						if(parse_config_file(configFile,playerConfig)==0)
						{
							config_file_ready=true;
							process_button_release(event.number,playerConfig);
						}
					}
					else
						process_button_release(event.number,playerConfig);
				}
				break;
				//case JS_EVENT_AXIS:
				//    axis = get_axis_state(&event, axes);
				//    if (axis < 3)
				//        printf("Axis %zu at (%6d, %6d)\n", axis, axes[axis].x, axes[axis].y);
				//    break;
			default:
				/* Ignore init events. */
			break;
		}

		fflush(stdout);
	}
	close(js);
	return 0;
}
/*****************************************************************************/

