#!/usr/bin/env python3
"""
Stop All Playback script for Media-Mux.
Stops video playback on all media-mux devices (master + slaves).
Uses the media-mux-stop-kodi-players.sh script for proper device discovery.
"""

import xbmc
import xbmcgui
import subprocess
import os

USB_MOUNT_POINT = "/media/usb"
STOP_SCRIPT = "/home/pi/media-mux/media-mux-stop-kodi-players.sh"


def is_master():
    """Check if USB storage is mounted (indicates master mode)"""
    return os.path.ismount(USB_MOUNT_POINT)


def run_stop_all():
    """Stop playback on all media-mux devices using the stop script"""
    progress = xbmcgui.DialogProgress()
    progress.create("Media-Mux Stop", "Stopping playback on all screens...")

    try:
        progress.update(25, "Discovering devices...")

        result = subprocess.run(
            [STOP_SCRIPT],
            capture_output=True,
            text=True,
            timeout=30
        )

        progress.close()

        # Parse output to get the count (e.g., "Stopped 3/3 players")
        output = result.stdout.strip()

        if result.returncode == 0:
            xbmcgui.Dialog().notification(
                "Media-Mux",
                output if output else "All players stopped",
                xbmcgui.NOTIFICATION_INFO,
                3000
            )
        else:
            xbmcgui.Dialog().notification(
                "Media-Mux",
                output if output else "Stop failed",
                xbmcgui.NOTIFICATION_ERROR,
                5000
            )
            xbmc.log(f"MediaMux Stop failed: {result.stderr}", xbmc.LOGERROR)

    except subprocess.TimeoutExpired:
        progress.close()
        xbmcgui.Dialog().notification(
            "Media-Mux",
            "Stop timeout",
            xbmcgui.NOTIFICATION_ERROR,
            5000
        )
    except Exception as e:
        progress.close()
        xbmcgui.Dialog().notification(
            "Media-Mux",
            f"Error: {str(e)}",
            xbmcgui.NOTIFICATION_ERROR,
            5000
        )
        xbmc.log(f"MediaMux Stop error: {str(e)}", xbmc.LOGERROR)


if __name__ == "__main__":
    if is_master():
        run_stop_all()
    else:
        xbmcgui.Dialog().notification(
            "Media-Mux",
            "Not master (no USB storage)",
            xbmcgui.NOTIFICATION_WARNING,
            3000
        )
