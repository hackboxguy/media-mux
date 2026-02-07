# Media-Mux Sync Kodi Add-on v1.2

Adds a "Sync" button to the Kodi video player OSD for triggering multi-screen synchronization.

## Features

- **OSD Button** - "Sync" button in video player OSD (tap screen to show)
- **Custom Icon** - Distinctive sync icon in the button bar
- **Keyboard shortcut** - Press 'S' during video playback
- **Touch-friendly** - Works with USB HID touch screens

## Automatic Installation (Recommended)

The add-on is automatically installed by `setup-selfhosted.sh`:

```bash
cd /home/pi/media-mux
sudo ./setup-selfhosted.sh
```

This installs:
- The add-on to `~/.kodi/addons/service.mediamux.sync/`
- Patched Estuary skin with Sync button to `~/.kodi/addons/skin.estuary/`
- Custom sync icon
- Keyboard mapping for 'S' key

## Manual Installation

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

# Copy custom icon
mkdir -p ~/.kodi/addons/skin.estuary/media/osd/fullscreen/buttons
cp ~/.kodi/addons/service.mediamux.sync/media-mux-sync.png \
   ~/.kodi/addons/skin.estuary/media/osd/fullscreen/buttons/

# Copy patched VideoOSD.xml
cp ~/.kodi/addons/service.mediamux.sync/VideoOSD.xml \
   ~/.kodi/addons/skin.estuary/xml/

# Copy keymap
mkdir -p ~/.kodi/userdata/keymaps
cp ~/.kodi/addons/service.mediamux.sync/resources/keymaps/mediamux.xml \
   ~/.kodi/userdata/keymaps/

# Restart Kodi
sudo systemctl restart kodi
```

## How to Use

### Option 1: OSD Button (Touch-Friendly)

1. Start playing a video
2. **Tap the screen** (or press any key) to show the OSD
3. Look for the **Sync icon** button at the right end of the button bar
4. Tap it to synchronize all screens

### Option 2: Keyboard Shortcut

1. During video playback
2. Press **'S'** key
3. Sync starts immediately

### Option 3: Programs Menu

1. Go to **Programs → Add-ons → Media-Mux Sync**
2. Run the add-on (only works if video is playing)

## How It Works

1. Add-on checks if USB is mounted at `/media/usb` (master detection)
2. If master + video playing → sync is available
3. Shows progress dialog during sync
4. Shows notification with result (success/failure)

## File Structure

```
~/.kodi/addons/
├── service.mediamux.sync/          # The add-on
│   ├── addon.xml
│   ├── service.py
│   ├── default.py
│   ├── context.py
│   └── resources/keymaps/mediamux.xml
│
└── skin.estuary/                   # Patched skin
    ├── xml/VideoOSD.xml            # Modified with Sync button
    └── media/osd/fullscreen/buttons/
        └── media-mux-sync.png      # Custom 74x74 icon
```

## Troubleshooting

### Sync button not appearing

1. Make sure skin is patched: Check `~/.kodi/addons/skin.estuary/xml/VideoOSD.xml` contains "mediamux"
2. Make sure add-on is enabled: Settings → Add-ons → My add-ons → Services
3. Check Kodi log: `cat ~/.kodi/temp/kodi.log | grep -i mediamux`

### Wrong icon showing

1. Verify icon exists: `ls ~/.kodi/addons/skin.estuary/media/osd/fullscreen/buttons/media-mux-sync.png`
2. Restart Kodi to reload textures

### Sync not working

1. Verify USB is mounted: `mount | grep /media/usb`
2. Test sync script manually:
   ```bash
   /home/pi/media-mux/media-mux-sync-kodi-players.sh --master=$(hostname)
   ```
