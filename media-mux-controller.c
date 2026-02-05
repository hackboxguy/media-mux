//
// media-mux-controller.c
// Generic keyboard monitor that grabs all keyboard devices and triggers sync on KEY_1
//
// Based on: https://raspberry-projects.com/pi/programming-in-c/keyboard-programming-in-c/reading-raw-keyboard-input
//

#include <linux/input.h>
#include <linux/input-event-codes.h>
#include <fcntl.h>
#include <unistd.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <dirent.h>
#include <sys/ioctl.h>
#include <sys/select.h>
#include <errno.h>

#define MAX_DEVICES 16
#define BITS_PER_LONG (sizeof(long) * 8)
#define NBITS(x) ((((x)-1)/BITS_PER_LONG)+1)
#define TEST_BIT(bit, array) ((array[(bit)/BITS_PER_LONG] >> ((bit)%BITS_PER_LONG)) & 1)

// Device info structure
typedef struct {
	int fd;
	char path[256];
	char name[256];
	unsigned short vendor;
	unsigned short product;
} InputDevice;

// Check if device is a keyboard (has letter/number keys, not just a mouse)
int is_keyboard(int fd)
{
	unsigned long evbits[NBITS(EV_MAX)] = {0};
	unsigned long keybits[NBITS(KEY_MAX)] = {0};
	unsigned long relbits[NBITS(REL_MAX)] = {0};

	// Get supported event types
	if (ioctl(fd, EVIOCGBIT(0, sizeof(evbits)), evbits) < 0)
		return 0;

	// Must have EV_KEY
	if (!TEST_BIT(EV_KEY, evbits))
		return 0;

	// Get supported keys
	if (ioctl(fd, EVIOCGBIT(EV_KEY, sizeof(keybits)), keybits) < 0)
		return 0;

	// Check for letter keys (A-Z) - a real keyboard has these
	int has_letters = 0;
	for (int key = KEY_Q; key <= KEY_P; key++) {  // Top row letters
		if (TEST_BIT(key, keybits)) {
			has_letters = 1;
			break;
		}
	}

	// Also check for number keys (1-0)
	int has_numbers = 0;
	for (int key = KEY_1; key <= KEY_0; key++) {
		if (TEST_BIT(key, keybits)) {
			has_numbers = 1;
			break;
		}
	}

	// A keyboard should have letters or numbers
	if (!has_letters && !has_numbers)
		return 0;

	// Check if it's primarily a mouse (has relative axes)
	if (TEST_BIT(EV_REL, evbits)) {
		if (ioctl(fd, EVIOCGBIT(EV_REL, sizeof(relbits)), relbits) >= 0) {
			// If it has X/Y relative movement, it's likely a mouse
			if (TEST_BIT(REL_X, relbits) && TEST_BIT(REL_Y, relbits)) {
				// But some keyboards also report as mice - check name
				char name[256] = "";
				ioctl(fd, EVIOCGNAME(sizeof(name)), name);
				// If name contains "Mouse" and doesn't contain "Keyboard", skip it
				if (strstr(name, "Mouse") && !strstr(name, "Keyboard") && !strstr(name, "RGB"))
					return 0;
			}
		}
	}

	return 1;
}

// Scan for all keyboard devices
int scan_keyboards(InputDevice *devices, int max_devices)
{
	DIR *dir;
	struct dirent *entry;
	char path[256];
	int count = 0;
	int fd;
	unsigned short id[4];

	dir = opendir("/dev/input");
	if (!dir) {
		perror("Cannot open /dev/input");
		return 0;
	}

	while ((entry = readdir(dir)) != NULL && count < max_devices) {
		// Only look at event* devices
		if (strncmp(entry->d_name, "event", 5) != 0)
			continue;

		snprintf(path, sizeof(path), "/dev/input/%s", entry->d_name);

		fd = open(path, O_RDONLY | O_NONBLOCK);
		if (fd < 0)
			continue;

		// Check if this is a keyboard
		if (is_keyboard(fd)) {
			// Get device info
			devices[count].fd = fd;
			strncpy(devices[count].path, path, sizeof(devices[count].path) - 1);
			devices[count].name[0] = '\0';
			ioctl(fd, EVIOCGNAME(sizeof(devices[count].name)), devices[count].name);

			if (ioctl(fd, EVIOCGID, id) == 0) {
				devices[count].vendor = id[ID_VENDOR];
				devices[count].product = id[ID_PRODUCT];
			} else {
				devices[count].vendor = 0;
				devices[count].product = 0;
			}

			count++;
		} else {
			close(fd);
		}
	}

	closedir(dir);
	return count;
}

// Print usage
void print_usage(const char *progname)
{
	printf("Usage: %s [OPTIONS]\n", progname);
	printf("\n");
	printf("Monitor all keyboard devices and trigger sync on KEY_1 press.\n");
	printf("Automatically detects and grabs all keyboards, ignoring mice.\n");
	printf("\n");
	printf("Options:\n");
	printf("  -h, --help     Show this help message\n");
	printf("  -l, --list     List all input devices (keyboards and others)\n");
	printf("  -n, --no-grab  Don't take exclusive access to devices\n");
	printf("  -v, --verbose  Print all key events\n");
	printf("\n");
	printf("Key actions:\n");
	printf("  KEY_1 -> Trigger sync script\n");
	printf("  KEY_2 -> (reserved)\n");
	printf("  KEY_3 -> (reserved)\n");
}

// List all input devices
void list_devices(void)
{
	DIR *dir;
	struct dirent *entry;
	char path[256];
	char name[256];
	int fd;
	unsigned short id[4];

	dir = opendir("/dev/input");
	if (!dir) {
		perror("Cannot open /dev/input");
		return;
	}

	printf("Input devices:\n");
	printf("%-20s %-10s %-8s %s\n", "Device", "VID:PID", "Type", "Name");
	printf("%-20s %-10s %-8s %s\n", "------", "-------", "----", "----");

	while ((entry = readdir(dir)) != NULL) {
		if (strncmp(entry->d_name, "event", 5) != 0)
			continue;

		snprintf(path, sizeof(path), "/dev/input/%s", entry->d_name);

		fd = open(path, O_RDONLY | O_NONBLOCK);
		if (fd < 0)
			continue;

		name[0] = '\0';
		ioctl(fd, EVIOCGNAME(sizeof(name)), name);

		const char *type = is_keyboard(fd) ? "KEYBOARD" : "other";

		if (ioctl(fd, EVIOCGID, id) == 0) {
			printf("%-20s %04x:%04x  %-8s %s\n", path, id[ID_VENDOR], id[ID_PRODUCT], type, name);
		} else {
			printf("%-20s ????:????  %-8s %s\n", path, type, name);
		}
		close(fd);
	}

	closedir(dir);
}

int main(int argc, char *argv[])
{
	InputDevice devices[MAX_DEVICES];
	int device_count = 0;
	int do_grab = 1;
	int verbose = 0;
	struct input_event ev;
	fd_set readfds;
	int max_fd = 0;

	// Parse command line arguments
	for (int i = 1; i < argc; i++) {
		if (strcmp(argv[i], "-h") == 0 || strcmp(argv[i], "--help") == 0) {
			print_usage(argv[0]);
			return 0;
		}
		else if (strcmp(argv[i], "-l") == 0 || strcmp(argv[i], "--list") == 0) {
			list_devices();
			return 0;
		}
		else if (strcmp(argv[i], "-n") == 0 || strcmp(argv[i], "--no-grab") == 0) {
			do_grab = 0;
		}
		else if (strcmp(argv[i], "-v") == 0 || strcmp(argv[i], "--verbose") == 0) {
			verbose = 1;
		}
		else {
			fprintf(stderr, "Unknown option: %s\n", argv[i]);
			print_usage(argv[0]);
			return 1;
		}
	}

	// Scan for keyboards
	printf("Scanning for keyboard devices...\n");
	device_count = scan_keyboards(devices, MAX_DEVICES);

	if (device_count == 0) {
		fprintf(stderr, "No keyboard devices found.\n");
		fprintf(stderr, "Use --list to see all input devices.\n");
		return 1;
	}

	printf("Found %d keyboard(s):\n", device_count);
	for (int i = 0; i < device_count; i++) {
		printf("  [%d] %s: %s (vendor=%04x, product=%04x)\n",
			   i, devices[i].path, devices[i].name,
			   devices[i].vendor, devices[i].product);
	}

	// Take exclusive access to all keyboards
	if (do_grab) {
		printf("Taking exclusive access to keyboards...\n");
		for (int i = 0; i < device_count; i++) {
			if (ioctl(devices[i].fd, EVIOCGRAB, 1) < 0) {
				fprintf(stderr, "  WARNING: Cannot grab %s: %s\n",
						devices[i].path, strerror(errno));
			} else {
				printf("  Grabbed: %s\n", devices[i].path);
			}
		}
	} else {
		printf("Running without exclusive access (--no-grab)\n");
	}

	printf("\nListening for key events...\n");
	printf("  KEY_1 -> trigger sync\n");
	printf("  KEY_2 -> (reserved)\n");
	printf("  KEY_3 -> (reserved)\n");
	printf("\n");

	// Main event loop using select()
	while (1) {
		FD_ZERO(&readfds);
		max_fd = 0;

		for (int i = 0; i < device_count; i++) {
			if (devices[i].fd >= 0) {
				FD_SET(devices[i].fd, &readfds);
				if (devices[i].fd > max_fd)
					max_fd = devices[i].fd;
			}
		}

		// Wait for events on any device
		int ret = select(max_fd + 1, &readfds, NULL, NULL, NULL);
		if (ret < 0) {
			if (errno == EINTR)
				continue;
			perror("select");
			break;
		}

		// Check each device for events
		for (int i = 0; i < device_count; i++) {
			if (devices[i].fd < 0 || !FD_ISSET(devices[i].fd, &readfds))
				continue;

			// Read events from this device
			while (read(devices[i].fd, &ev, sizeof(ev)) == sizeof(ev)) {
				if (ev.type != EV_KEY)
					continue;

				// Key release (value == 0)
				if (ev.value == 0) {
					if (verbose) {
						printf("[%s] Key up: %d\n", devices[i].name, ev.code);
					}

					switch (ev.code) {
						case KEY_1:
							printf("KEY_1 pressed - triggering sync...\n");
							system("/home/pi/media-mux/media-mux-sync-kodi-players.sh");
							printf("Sync complete\n");
							break;
						case KEY_2:
							printf("KEY_2 pressed (reserved)\n");
							break;
						case KEY_3:
							printf("KEY_3 pressed (reserved)\n");
							break;
						default:
							if (verbose) {
								printf("Key %d released (ignored)\n", ev.code);
							}
							break;
					}
				}
				else if (ev.value == 1 && verbose) {
					printf("[%s] Key down: %d\n", devices[i].name, ev.code);
				}
			}
		}
	}

	// Cleanup
	for (int i = 0; i < device_count; i++) {
		if (devices[i].fd >= 0) {
			if (do_grab)
				ioctl(devices[i].fd, EVIOCGRAB, 0);
			close(devices[i].fd);
		}
	}

	return 0;
}
