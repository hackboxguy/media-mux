#!/usr/bin/env python3
"""
Media-Mux Sync Service for Kodi

Adds "Sync All Screens" to the video player context menu (long-press menu).
Only available on master device (USB storage mounted).
"""

import xbmc
import xbmcgui
import xbmcaddon
import subprocess
import os

# Constants
USB_MOUNT_POINT = "/media/usb"
SYNC_SCRIPT = "/home/pi/media-mux/media-mux-sync-kodi-players.sh"


def is_master():
    """Check if USB storage is mounted (indicates master mode)"""
    return os.path.ismount(USB_MOUNT_POINT)


def run_sync():
    """Execute the sync script and show result"""
    # Show progress dialog
    progress = xbmcgui.DialogProgress()
    progress.create("Media-Mux Sync", "Synchronizing all screens...")

    try:
        # Get hostname for --master parameter
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
        xbmcgui.Dialog().notification(
            "Media-Mux",
            "Sync timeout",
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
        xbmc.log(f"MediaMux Sync error: {str(e)}", xbmc.LOGERROR)


class MediaMuxPlayer(xbmc.Player):
    """Custom player to add sync option to OSD"""

    def __init__(self):
        super().__init__()
        self.sync_shown = False


class MediaMuxSyncService:
    """
    Service that monitors for a custom action to trigger sync.

    The sync can be triggered by:
    1. Mapped key in keymap (recommended for touch)
    2. Running the addon directly from Programs menu
    """

    def __init__(self):
        self.monitor = xbmc.Monitor()

    def run(self):
        """Main service loop - just keeps addon alive"""
        xbmc.log("MediaMux Sync Service started", xbmc.LOGINFO)

        # Check if we're master and log status
        if is_master():
            xbmc.log("MediaMux: Running in MASTER mode (USB detected)", xbmc.LOGINFO)
            xbmcgui.Dialog().notification(
                "Media-Mux",
                "Master mode - Sync available",
                xbmcgui.NOTIFICATION_INFO,
                3000
            )
        else:
            xbmc.log("MediaMux: Running in SLAVE mode (no USB)", xbmc.LOGINFO)

        # Keep service running (for future enhancements)
        while not self.monitor.abortRequested():
            if self.monitor.waitForAbort(10):
                break

        xbmc.log("MediaMux Sync Service stopped", xbmc.LOGINFO)


if __name__ == "__main__":
    # Check if running as service or invoked directly
    addon = xbmcaddon.Addon()

    # If invoked with RunScript, run sync
    import sys
    if len(sys.argv) > 1 and sys.argv[1] == "sync":
        if is_master():
            run_sync()
        else:
            xbmcgui.Dialog().notification(
                "Media-Mux",
                "Not master - no USB storage",
                xbmcgui.NOTIFICATION_WARNING,
                3000
            )
    else:
        # Running as service
        service = MediaMuxSyncService()
        service.run()
