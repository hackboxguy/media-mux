#!/usr/bin/env python3
"""
Direct invocation script for Media-Mux Sync.
Can be run from Programs menu or via keymap.
"""

import xbmc
import xbmcgui
import subprocess
import os

USB_MOUNT_POINT = "/media/usb"
SYNC_SCRIPT = "/home/pi/media-mux/media-mux-sync-kodi-players.sh"


def is_master():
    return os.path.ismount(USB_MOUNT_POINT)


def is_video_playing():
    return xbmc.Player().isPlayingVideo()


def run_sync():
    progress = xbmcgui.DialogProgress()
    progress.create("Media-Mux Sync", "Synchronizing all screens...")

    try:
        hostname = subprocess.check_output(["hostname"]).decode().strip()
        progress.update(25, "Discovering devices...")

        result = subprocess.run(
            [SYNC_SCRIPT, f"--master={hostname}"],
            capture_output=True,
            text=True,
            timeout=60
        )

        progress.close()

        if result.returncode == 0:
            xbmcgui.Dialog().notification(
                "Media-Mux",
                "All screens synchronized!",
                xbmcgui.NOTIFICATION_INFO,
                3000
            )
        else:
            xbmcgui.Dialog().notification(
                "Media-Mux",
                "Sync failed",
                xbmcgui.NOTIFICATION_ERROR,
                5000
            )
            xbmc.log(f"MediaMux Sync failed: {result.stderr}", xbmc.LOGERROR)

    except subprocess.TimeoutExpired:
        progress.close()
        xbmcgui.Dialog().notification("Media-Mux", "Timeout", xbmcgui.NOTIFICATION_ERROR, 5000)
    except Exception as e:
        progress.close()
        xbmcgui.Dialog().notification("Media-Mux", f"Error", xbmcgui.NOTIFICATION_ERROR, 5000)
        xbmc.log(f"MediaMux error: {str(e)}", xbmc.LOGERROR)


if __name__ == "__main__":
    if not is_master():
        xbmcgui.Dialog().notification(
            "Media-Mux",
            "Not master (no USB storage)",
            xbmcgui.NOTIFICATION_WARNING,
            3000
        )
    elif not is_video_playing():
        xbmcgui.Dialog().notification(
            "Media-Mux",
            "No video playing",
            xbmcgui.NOTIFICATION_WARNING,
            3000
        )
    else:
        run_sync()
