# Media-Mux Sync Kodi Add-on v1.3

Adds touch-friendly "Sync" and "Stop All" buttons to the Kodi video player OSD for controlling multi-screen synchronized playback.

## Features

- **OSD Sync Button** - "Sync" button in video player OSD (tap screen to show)
- **OSD Stop All Button** - "Stop All" button to stop playback on all screens
- **Master-only visibility** - Buttons only appear on master device (USB storage mounted)
- **Custom Icons** - Distinctive sync and stop icons in the button bar
- **Keyboard shortcut** - Press 'S' during video playback to sync
- **Touch-friendly** - Works with USB HID touch screens
- **No external hardware needed** - Replaces the need for 3-key push button for triggering sync

## What's New in v1.3

- **Master-only OSD buttons** - Sync/Stop buttons automatically hide on slave devices
- **Pre-configured addon database** - No more "Do you want to enable this addon?" prompts
- **Version check disabled** - No more "new version available" popup on startup
- **Bootable SD card support** - Full auto-installation via custom-pi-imager scripts
- **Accurate device count** - Fixed duplicate localhost counting (shows correct 3/3 instead of 4/4)

## Installation Methods

### Method 1: Bootable SD Card Image (Recommended)

Use the custom-pi-imager to create a fully configured SD card:

```bash
# On your build machine
cd misc-tools
./custom-pi-imager.sh \
    --base-image=raspios-bookworm-arm64-lite.img \
    --setup-hook-list=./board-configs/media-mux/media-mux-packages-selfhosted-dlna.txt \
    --output-dir=/tmp/media-mux-image
```

This creates an SD card image with:
- All media-mux components pre-installed
- Kodi addon and skin already configured
- Addons database pre-configured (no prompts)
- Self-hosted DHCP/DLNA/NTP support

### Method 2: Manual Setup Script

Run on an existing Pi with Kodi installed:

```bash
cd /home/pi/media-mux
sudo ./setup-selfhosted.sh
```

This installs:
- The add-on to `~/.kodi/addons/service.mediamux.sync/`
- Patched Estuary skin with Sync/Stop buttons
- Custom icons for both buttons
- Keyboard mapping for 'S' key
- Pre-configured Addons database (no prompts)

### Method 3: Manual Installation

If you need to install manually:

```bash
# SSH to Pi
ssh pi@<hostname>

# Remove old version
rm -rf ~/.kodi/addons/service.mediamux.sync

# Copy add-on (from your dev machine first)
cp -r /tmp/service.mediamux.sync ~/.kodi/addons/

# Copy Estuary skin to user directory
cp -r /usr/share/kodi/addons/skin.estuary ~/.kodi/addons/

# Copy custom icons
mkdir -p ~/.kodi/addons/skin.estuary/media/osd/fullscreen/buttons
cp ~/.kodi/addons/service.mediamux.sync/start-sync-playback.png \
   ~/.kodi/addons/skin.estuary/media/osd/fullscreen/buttons/
cp ~/.kodi/addons/service.mediamux.sync/stop-sync-playback.png \
   ~/.kodi/addons/skin.estuary/media/osd/fullscreen/buttons/

# Copy patched VideoOSD.xml
cp ~/.kodi/addons/service.mediamux.sync/VideoOSD.xml \
   ~/.kodi/addons/skin.estuary/xml/

# Copy keymap
mkdir -p ~/.kodi/userdata/keymaps
cp ~/.kodi/addons/service.mediamux.sync/resources/keymaps/mediamux.xml \
   ~/.kodi/userdata/keymaps/

# Copy pre-configured database (optional - suppresses prompts)
mkdir -p ~/.kodi/userdata/Database
cp ~/media-mux/kodi-addon/templates/Database/Addons33.db \
   ~/.kodi/userdata/Database/

# Restart Kodi
sudo systemctl restart kodi
```

## How to Use

### Option 1: OSD Buttons (Touch-Friendly)

1. Start playing a video on the **master device** (the one with USB storage)
2. **Tap the screen** (or press any key) to show the OSD
3. Look for the **Sync** and **Stop All** buttons at the right end of the button bar:
   - **Sync** - "Sync all screens" - Synchronizes playback position across all screens
   - **Stop All** - "Stop all screens" - Stops playback on all screens (master + slaves)

**Note:** These buttons only appear on the master device (USB mounted). Slave devices won't see them.

### Option 2: Keyboard Shortcut

1. During video playback on master
2. Press **'S'** key
3. Sync starts immediately

### Option 3: Programs Menu

1. Go to **Programs → Add-ons → Media-Mux Sync**
2. Run the add-on (only works if video is playing and device is master)

## How It Works

1. Add-on service runs in background, checking USB mount status every 5 seconds
2. Sets a skin property `mediamux.ismaster` when USB is mounted at `/media/usb`
3. OSD buttons use this property for visibility (master-only)
4. When Sync/Stop is triggered:
   - Shows progress dialog
   - Discovers all media-mux devices via mDNS
   - Sends commands to all players
   - Shows notification with result (e.g., "Stopped 3/3 players")

## File Structure

```
~/.kodi/addons/
├── service.mediamux.sync/          # The add-on
│   ├── addon.xml
│   ├── service.py                  # Background service (sets master property)
│   ├── default.py                  # Sync script handler
│   ├── stop.py                     # Stop all playback handler
│   ├── context.py
│   └── resources/keymaps/mediamux.xml
│
└── skin.estuary/                   # Patched skin
    ├── xml/VideoOSD.xml            # Modified with Sync + Stop buttons
    └── media/osd/fullscreen/buttons/
        ├── start-sync-playback.png # Sync icon (74x74)
        └── stop-sync-playback.png  # Stop icon (74x74)

~/.kodi/userdata/
├── Database/
│   └── Addons33.db                 # Pre-configured (addon enabled, version-check disabled)
└── keymaps/
    └── mediamux.xml                # 'S' key mapping
```

## Troubleshooting

### Sync/Stop buttons not appearing

1. **Check if master**: Buttons only show on master device (USB mounted)
   ```bash
   mount | grep /media/usb
   ```
2. **Check skin is patched**:
   ```bash
   grep -l "mediamux" ~/.kodi/addons/skin.estuary/xml/VideoOSD.xml
   ```
3. **Check add-on is enabled**: Settings → Add-ons → My add-ons → Services
4. **Check Kodi log**:
   ```bash
   grep -i mediamux ~/.kodi/temp/kodi.log
   ```

### Wrong icon showing

1. Verify icons exist:
   ```bash
   ls ~/.kodi/addons/skin.estuary/media/osd/fullscreen/buttons/
   ```
2. Restart Kodi to reload textures

### Sync not working

1. Verify USB is mounted: `mount | grep /media/usb`
2. Test sync script manually:
   ```bash
   /home/pi/media-mux/media-mux-sync-kodi-players.sh --master=$(hostname)
   ```

### "Do you want to enable this addon?" prompt appears

The Addons33.db template wasn't installed. Copy it manually:
```bash
cp ~/media-mux/kodi-addon/templates/Database/Addons33.db ~/.kodi/userdata/Database/
sudo systemctl restart kodi
```

### Device count shows wrong number (e.g., 4/4 instead of 3/3)

This was fixed in v1.3. Update your sync/stop scripts:
```bash
cd ~/media-mux && git pull
```
