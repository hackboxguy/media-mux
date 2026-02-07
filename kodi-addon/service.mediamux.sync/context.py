#!/usr/bin/env python3
"""
Context menu handler for Media-Mux Sync.
Called when user selects "Sync All Screens" from video context menu.
"""

import xbmc
import xbmcgui
import subprocess
import os

USB_MOUNT_POINT = "/media/usb"
SYNC_SCRIPT = "/home/pi/media-mux/media-mux-sync-kodi-players.sh"


def is_master():
    """Check if USB storage is mounted (indicates master mode)"""
    return os.path.ismount(USB_MOUNT_POINT)


def run_sync():
    """Execute the sync script and show result"""
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
                "Sync failed - check logs",
                xbmcgui.NOTIFICATION_ERROR,
                5000
            )
            xbmc.log(f"MediaMux Sync failed: {result.stderr}", xbmc.LOGERROR)

    except subprocess.TimeoutExpired:
        progress.close()
        xbmcgui.Dialog().notification("Media-Mux", "Sync timeout", xbmcgui.NOTIFICATION_ERROR, 5000)
    except Exception as e:
        progress.close()
        xbmcgui.Dialog().notification("Media-Mux", f"Error: {str(e)}", xbmcgui.NOTIFICATION_ERROR, 5000)
        xbmc.log(f"MediaMux Sync error: {str(e)}", xbmc.LOGERROR)


if __name__ == "__main__":
    if is_master():
        run_sync()
    else:
        xbmcgui.Dialog().notification(
            "Media-Mux",
            "Not master device (no USB)",
            xbmcgui.NOTIFICATION_WARNING,
            3000
        )
