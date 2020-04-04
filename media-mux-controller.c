//original example taken from : https://raspberry-projects.com/pi/programming-in-c/keyboard-programming-in-c/reading-raw-keyboard-input
#include <linux/input.h>
#include <linux/input-event-codes.h>
#include <fcntl.h>  //for open()
#include <unistd.h> // for close()
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

#define BITS_PER_LONG (sizeof(long) * 8)
#define NBITS(x) ((((x)-1)/BITS_PER_LONG)+1)
#define INPUT_DEVICE "/dev/input/by-id/usb-05a4_9881-event-kbd"
//#define INPUT_DEVICE "/dev/input/event0"

int main (void)
{
	int FileDevice;
	int ReadDevice;
	int Index;
	struct input_event InputEvent[64];
	int version;
	unsigned short id[4];
	unsigned long bit[EV_MAX][NBITS(KEY_MAX)];

	//----- OPEN THE INPUT DEVICE -----
	if ((FileDevice = open(INPUT_DEVICE, O_RDONLY)) < 0)		//<<<<SET THE INPUT DEVICE PATH HERE
	{
		perror("KeyboardMonitor can't open input device");
		close(FileDevice);
		return -1;
	}

	//----- GET DEVICE VERSION -----
	if (ioctl(FileDevice, EVIOCGVERSION, &version))
	{
		perror("KeyboardMonitor can't get version");
		close(FileDevice);
		return -1;
	}
	//printf("Input driver version is %d.%d.%d\n", version >> 16, (version >> 8) & 0xff, version & 0xff);

	//----- GET DEVICE INFO -----
	ioctl(FileDevice, EVIOCGID, id);
	//printf("Input device ID: bus 0x%x vendor 0x%x product 0x%x version 0x%x\n", id[ID_BUS], id[ID_VENDOR], id[ID_PRODUCT], id[ID_VERSION]);
	
	memset(bit, 0, sizeof(bit));
	ioctl(FileDevice, EVIOCGBIT(0, EV_MAX), bit[0]);

	//----- READ KEYBOARD EVENTS -----
	while (1)
	{
		ReadDevice = read(FileDevice, InputEvent, sizeof(struct input_event) * 64);

		if (ReadDevice < (int) sizeof(struct input_event))
		{
			//This should never happen
			//perror("KeyboardMonitor error reading - keyboard lost?");
			close(FileDevice);
			return -1;
		}
		else
		{
			for (Index = 0; Index < ReadDevice / sizeof(struct input_event); Index++)
			{
				//We have:
				//	InputEvent[Index].time		timeval: 16 bytes (8 bytes for seconds, 8 bytes for microseconds)
				//	InputEvent[Index].type		See input-event-codes.h
				//	InputEvent[Index].code		See input-event-codes.h
				//	InputEvent[Index].value		01 for keypress, 00 for release, 02 for autorepeat
				if (InputEvent[Index].type == EV_KEY)
				{
					if (InputEvent[Index].value == 2)
					{
						printf("Auto-repeat: %d\n",InputEvent[Index].code);
					}
					else if (InputEvent[Index].value == 1)
					{
						printf("key_down   : %d\n",InputEvent[Index].code);
					}
					else if (InputEvent[Index].value == 0)
					{
						printf("key_up     : %d\n",InputEvent[Index].code);
						switch(InputEvent[Index].code)
						{
							case KEY_DOWN     :break;
							case KEY_UP       :break;
							case KEY_RIGHT    :break;
							case KEY_LEFT     :break;
							case KEY_ENTER    :break;
							case KEY_KP0      :break;
							case KEY_KP1      :system("/home/pi/media-mux/media-mux-play-batch.sh -u udp://@239.255.42.61:5004");break;
							case KEY_KP2      :system("/home/pi/media-mux/media-mux-play-batch.sh -u udp://@239.255.42.62:5004");break;
							case KEY_KP3      :system("/home/pi/media-mux/media-mux-play-batch.sh -u udp://@239.255.42.64:5004");break;
							case KEY_KP4      :break;
							case KEY_KP5      :break;
							case KEY_KP6      :break;
							case KEY_KP7      :break;
							case KEY_KP8      :break;
							case KEY_KP9      :break;
							case KEY_BACKSPACE:break;
							case KEY_PAGEUP   :system("/home/pi/media-mux/media-mux-action-batch.sh -a volumeup");break; //channel + (hama-mce-remote)
							case KEY_PAGEDOWN :system("/home/pi/media-mux/media-mux-action-batch.sh -a volumedn");break; //channel - (hama-mce-remote)
							case KEY_ESC      :system("/home/pi/media-mux/media-mux-action-batch.sh -a stop");break;//key clear on hama-mce-remote
							default           :break; //unknown key
						}
					}
				}
			}
		}

	}

    return 0;
}