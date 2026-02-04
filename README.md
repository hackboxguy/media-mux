# Media-Mux: Synchronized Multi-Screen Kodi Playback

Media-Mux is a system for synchronizing video playback across multiple Raspberry Pi devices running Kodi. Perfect for video walls, multi-room displays, or any scenario where you need multiple screens playing the same content in "amost-perfect" sync.

## Architecture

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                              Network (LAN)                                   │
│                                                                              │
│  ┌─────────────────────┐                                                     │
│  │   Pocket Router     │                                                     │
│  │   (192.168.8.1)     │                                                     │
│  │                     │                                                     │
│  │  ┌───────────────┐  │                                                     │
│  │  │  DHCP Server  │  │                                                     │
│  │  │  DNS Server   │  │                                                     │
│  │  │  DLNA Server  │  │◄──── Media Library (USB Storage)                    │
│  │  │  :8200        │  │                                                     │
│  │  └───────────────┘  │                                                     │
│  └──────────┬──────────┘                                                     │
│             │                                                                │
│             │ Ethernet                                                       │
│             ▼                                                                │
│  ┌─────────────────────┐                                                     │
│  │   Network Switch    │                                                     │
│  └──┬───────┬───────┬──┘                                                     │
│     │       │       │                                                        │
│     │       │       │  Ethernet                                              │
│     ▼       ▼       ▼                                                        │
│  ┌──────┐ ┌──────┐ ┌──────┐                                                  │
│  │media-│ │media-│ │media-│    ┌─────────────────────────────────────────┐   │
│  │ mux- │ │ mux- │ │ mux- │    │ Communication:                          │   │
│  │ 0001 │ │ 0002 │ │ 0003 │    │  • Avahi/mDNS - Device Discovery        │   │
│  │Master│ │Slave │ │Slave │    │  • JSON-RPC   - Kodi Control (:8888)    │   │
│  │      │ │      │ │      │    │  • DLNA/HTTP  - Media Streaming (:8200) │   │
│  │ Kodi │ │ Kodi │ │ Kodi │    └─────────────────────────────────────────┘   │
│  │:8888 │ │:8888 │ │:8888 │                                                  │
│  └──────┘ └──────┘ └──────┘                                                  │
│     │       │       │                                                        │
│     └───────┴───────┘                                                        │
│             │                                                                │
│      Sync Control via                                                        │
│      media-mux-sync-kodi-players.sh                                          │
└──────────────────────────────────────────────────────────────────────────────┘
```

### Network Components

| Component | Role | IP/Port |
|-----------|------|---------|
| Pocket Router | DHCP, DNS, DLNA media server | 192.168.8.1:8200 |
| Network Switch | Connects all devices via Ethernet | - |
| media-mux-0001 | Master Kodi player | DHCP assigned, :8888 |
| media-mux-0002+ | Slave Kodi players | DHCP assigned, :8888 |

## How Synchronization Works

The `media-mux-sync-kodi-players.sh` script synchronizes all Kodi players on the network to play the same content at the same position. The sync achieves sub-200ms accuracy (typically <10ms spread between devices).

### Sync Flow

```
1. Query Master           Get currently playing file and position from master kodi-player
        │
        ▼
2. Discover Devices       Find all media-mux-* kodi-player devices via Avahi/mDNS
        │
        ▼
3. Stop All Players       Send Player.Stop to all discovered devices
        │
        ▼
4. Open File              Send Player.Open with master's file(dlna stream url) to all devices
        │
        ▼
5. Wait for Ready         Poll each device until file is loaded (totaltime > 0)
        │
        ▼
6. Kodisync               Pause all players at the exact same frame (--once mode)
        │
        ▼
7. Verify Kodisync        Check all players are within 1% of each other
        │                 If not, re-sync to minimum position
        ▼
8. Seek to Position       Seek all players to master's percentage position
        │                 Verify positions, retry up to 3 times if needed
        ▼
9. Final Sync Check       Ensure all players within 0.2% tolerance (~120ms)
        │                 Re-sync to minimum position if needed (up to 3 attempts)
        ▼
10. Resume Playback       Send Player.PlayPause to all devices simultaneously
```

### Key Technologies

- **Avahi/mDNS**: Automatic device discovery on the local network
- **Kodi JSON-RPC**: HTTP-based API for controlling Kodi (port 8888)
- **kodisync**: Node.js tool that pauses all players at the exact same frame
- **Position Verification**: Multi-stage verification ensures all devices are truly synced

### Sync Tolerance

The sync script ensures all players are within **0.2% position spread** before resuming playback:
- For a 60-second video: 0.2% = ~120ms = ~7 frames at 60fps
- Typical achieved spread: <0.02% (~12ms)

## Usage

### Basic Sync (Silent)
```bash
/home/pi/media-mux/media-mux-sync-kodi-players.sh --master=media-mux-0001
```

### Debug Mode (Verbose)
```bash
/home/pi/media-mux/media-mux-sync-kodi-players.sh --debuglog --master=media-mux-0001
```

### Options

| Option | Description |
|--------|-------------|
| `--master=<host>` | Specify master Kodi device (default: media-mux-0001) |
| `--debuglog` | Enable verbose debug output |
| `--help` | Show help message |

## Example Debug Output

```
pi@media-mux-0001:~/media-mux $ ./media-mux-sync-kodi-players.sh --debuglog --master=media-mux-0001

[DEBUG] Master host: media-mux-0001
{"id":"VideoGetItem","jsonrpc":"2.0","result":{"item":{"file":"http://192.168.8.1:8200/MediaItems/66.mp4",...}}}
[DEBUG] Playing file: http://192.168.8.1:8200/MediaItems/66.mp4
{"id":1,"jsonrpc":"2.0","result":{"percentage":9.09%,"time":{"hours":0,"milliseconds":459,"minutes":0,"seconds":5}}}
[DEBUG] Position: 9.09%
[DEBUG] Discovering devices via avahi-browse...
[DEBUG] Device list: 192.168.8.180 192.168.8.202 192.168.8.243
...
[DEBUG] kodisync devices:  192.168.8.180:8888 192.168.8.202:8888 192.168.8.243:8888
One-shot sync mode: will exit after sync (timeout: 20s)
Syncing 3 host(s): 192.168.8.180:8888, 192.168.8.202:8888, 192.168.8.243:8888
Syncing all together
Ready
Sync completed successfully
[DEBUG] kodisync exit code: 0
[DEBUG] Verifying kodisync sync result...
[DEBUG]   192.168.8.180: speed=0, position=6.74629%
[DEBUG]   192.168.8.202: speed=0, position=6.74629%
[DEBUG]   192.168.8.243: speed=0, position=6.74629%
[DEBUG] Position spread after kodisync: 0% (min: 6.74629%, max: 6.74629%)
[DEBUG] Target position: 9.09%
[DEBUG] Seek attempt 1 of 3
[DEBUG] Device 192.168.8.180 at 8.43% (target: 9.09%, diff: 0.66%)
[DEBUG] Device 192.168.8.202 at 8.88% (target: 9.09%, diff: 0.21%)
[DEBUG] Device 192.168.8.243 at 8.43% (target: 9.09%, diff: 0.66%)
[DEBUG] Seek verified successfully on attempt 1
[DEBUG] Final sync verification (attempt 1)...
[DEBUG] Final position spread: 0.0000% (min: 8.43869%, max: 8.43869%)
[DEBUG] All players synced within tolerance on attempt 1
[DEBUG] Sync finished successfully
```

### Understanding the Output

1. **Master Query**: Gets the file path and current position from the master
2. **Device Discovery**: Finds all media-mux devices via Avahi
3. **Stop/Open**: Stops current playback and opens the file on all devices
4. **Ready Check**: Polls until each device has the file loaded
5. **Kodisync**: Pauses all players at the same frame using `--once` mode
6. **Verify Kodisync**: Confirms all players are at the same position
7. **Seek to Master Position**: Seeks all to the captured master position
8. **Final Sync Check**: Ensures spread is within 0.2% tolerance
9. **Resume**: Starts playback on all devices simultaneously

## Stress Testing

A stress test script is included to verify sync reliability:

```bash
./stress-test-sync.sh --master=media-mux-0001 \
  --media=http://192.168.8.1:8200/MediaItems/66.mp4 \
  --loopcount=20 \
  --failstop=yes
```

### Stress Test Options

| Option | Description |
|--------|-------------|
| `--master=<host>` | Master Kodi device hostname (required) |
| `--media=<url>` | Media file URL to play (required) |
| `--loopcount=<n>` | Number of iterations (default: 20) |
| `--failstop=yes/no` | Stop on first failure (default: no) |

### Example Stress Test Results

```
==============================================
STRESS TEST SUMMARY
==============================================
Total iterations: 20 / 20
Duration: 528s

Results:
  PASS: 20 (100.0%)
  WARN: 0 (0.0%)
  FAIL: 0 (0.0%)

Spread statistics:
  Average: 0.0112%
  Maximum: 0.1382%

Full log: /home/pi/media-mux/stress-test-logs/stress-test-20260204_133812.log
==============================================
```

## Setup

### Prerequisites

- Raspberry Pi devices (tested with Pi 3/4/5)
- Raspbian/Raspberry Pi OS
- Network connectivity between all devices
- Shared media source accessible to all devices (e.g., DLNA server)

### Installation

```bash
# Clone the repository with submodules
git clone --recursive https://github.com/hackboxguy/media-mux.git
cd media-mux

# Run setup on each Pi
# For master (Pi #1):
sudo ./setup.sh -n 1

# For slaves (Pi #2, #3, etc.):
sudo ./setup.sh -n 2
sudo ./setup.sh -n 3
```

### Setup Options

```bash
sudo ./setup.sh -n <number> [OPTIONS]

Options:
  -n <number>   Pi sequence number (1 = master, 2+ = slave)
  --no-reboot   Skip automatic reboot after setup
  --help        Show help message
```

### What Setup Does

1. Creates autoplay symlink (master vs slave behavior)
2. Installs dependencies (avahi, kodi, nodejs, jq, etc.)
3. Configures Avahi service publishing
4. Sets hostname to `media-mux-XXXX`
5. Configures rc.local for startup
6. Compiles media-mux-controller
7. Sets up Kodi configuration
8. Installs kodisync npm dependencies

## Triggering Sync

### Manual (SSH)
```bash
ssh pi@media-mux-0001 '/home/pi/media-mux/media-mux-sync-kodi-players.sh --master=media-mux-0001'
```

### Via IR Remote / Keyboard
The `media-mux-controller` daemon listens for key presses:
- **KEY_1**: Triggers sync script

## Troubleshooting

### Check Logs
```bash
# Sync script logs to syslog
journalctl -t media-mux-sync -f

# Setup logs
cat /var/log/media-mux-setup.log

# Stress test logs
ls -la /home/pi/media-mux/stress-test-logs/
```

### Verify Device Discovery
```bash
avahi-browse -art | grep media-mux
```

### Test Kodi JSON-RPC
```bash
curl -s -X POST -H "content-type:application/json" \
  http://media-mux-0001:8888/jsonrpc \
  -d '{"jsonrpc":"2.0","method":"Player.GetActivePlayers","id":1}'
```

### Common Issues

| Issue | Solution |
|-------|----------|
| Devices not discovered | Check `avahi-daemon` is running: `systemctl status avahi-daemon` |
| Sync fails with timeout | Increase `KODISYNC_TIMEOUT` in sync script (default: 20s) |
| Position spread too high | Video may have sparse keyframes; try different content |
| kodisync not found | Run `cd kodisync && npm install` |

## Dependencies

- `avahi-daemon`, `avahi-utils` - mDNS discovery
- `kodi` - Media player
- `jq` - JSON processing
- `nodejs`, `npm` - For kodisync
- `curl` - HTTP requests
- `awk` - Floating point calculations

## File Structure

```
media-mux/
├── media-mux-sync-kodi-players.sh   # Main sync script
├── stress-test-sync.sh              # Stress testing tool
├── setup.sh                         # Installation script
├── media-mux-controller.c           # Keyboard/IR input handler
├── kodisync/                        # Git submodule - frame-accurate sync
│   └── kodisync.js                  # Modified with --once mode
├── rc.local                         # Startup script (slave)
├── rc.local.master                  # Startup script (master)
├── sources.xml                      # Kodi media sources config
├── guisettings.xml                  # Kodi settings
└── stress-test-logs/                # Stress test output logs
```

## Credits

- [kodisync](https://github.com/hackboxguy/kodisync) - Fork with `--once` mode for one-shot sync
- Original kodisync by [Bart Nagel](https://github.com/tremby/kodisync)
- Kodi JSON-RPC API

## License

MIT License
