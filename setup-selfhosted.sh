#!/bin/bash
#
# setup-selfhosted.sh
# Extends media-mux to act as DHCP/DNS/DLNA server when USB storage is detected
#
# This eliminates the need for an external pocket router.
# The Pi with USB storage becomes the network master.
#
# Usage:
#   sudo ./setup-selfhosted.sh
#
# After setup, on each boot:
#   - If USB storage detected → Master mode (static IP, DHCP, DLNA)
#   - If no USB storage → Slave mode (DHCP client, normal Kodi)
#

set -e

#------------------------------------------------------------------------------
# Configuration
#------------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
STATIC_IP="192.168.8.1"
NETMASK="24"
DHCP_RANGE_START="192.168.8.100"
DHCP_RANGE_END="192.168.8.200"
DHCP_LEASE_TIME="12h"
DLNA_PORT="8200"
USB_MOUNT_POINT="/media/usb"
ETH_INTERFACE="eth0"
LOG_FILE="/var/log/media-mux-selfhosted.log"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

#------------------------------------------------------------------------------
# Helper functions
#------------------------------------------------------------------------------
log() { echo -e "${GREEN}[setup-selfhosted]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

log_step() {
    printf "%-50s " "$1"
}

log_ok() {
    echo -e "${GREEN}[OK]${NC}"
}

log_skip() {
    echo -e "${YELLOW}[SKIP]${NC} $1"
}

#------------------------------------------------------------------------------
# Check root
#------------------------------------------------------------------------------
if [ "$EUID" -ne 0 ]; then
    error "Please run as root: sudo $0"
fi

echo ""
log "=============================================="
log "  Media-Mux Self-Hosted Setup"
log "=============================================="
echo ""
log "This script configures this Pi to act as:"
log "  - DHCP server (dnsmasq)"
log "  - DNS server (dnsmasq)"
log "  - DLNA media server (minidlna)"
log "  - NTP time server (chrony)"
log ""
log "Network: ${STATIC_IP}/${NETMASK}"
log "DHCP range: ${DHCP_RANGE_START} - ${DHCP_RANGE_END}"
log "DLNA port: ${DLNA_PORT}"
log "USB mount: ${USB_MOUNT_POINT}"
echo ""

#------------------------------------------------------------------------------
# Step 1: Install dependencies
#------------------------------------------------------------------------------
log_step "[1/11] Installing dnsmasq, minidlna, chrony, and sqlite3..."
apt-get update -qq
apt-get install -y -qq dnsmasq minidlna chrony sqlite3 > /dev/null 2>&1
log_ok

#------------------------------------------------------------------------------
# Step 2: Stop and disable services (will be started by boot script)
#------------------------------------------------------------------------------
log_step "[2/11] Configuring services..."
systemctl stop dnsmasq 2>/dev/null || true
systemctl stop minidlna 2>/dev/null || true
systemctl stop chrony 2>/dev/null || true
systemctl disable dnsmasq 2>/dev/null || true
systemctl disable minidlna 2>/dev/null || true
systemctl disable chrony 2>/dev/null || true
log_ok

#------------------------------------------------------------------------------
# Step 3: Create dnsmasq configuration
#------------------------------------------------------------------------------
log_step "[3/11] Creating dnsmasq configuration..."
cat > /etc/dnsmasq.d/media-mux-selfhosted.conf << EOF
# Media-Mux Self-Hosted DHCP/DNS Configuration
# This file is managed by setup-selfhosted.sh

# Interface to listen on
interface=${ETH_INTERFACE}
bind-interfaces

# DHCP range
dhcp-range=${DHCP_RANGE_START},${DHCP_RANGE_END},${DHCP_LEASE_TIME}

# Gateway (this device)
dhcp-option=3,${STATIC_IP}

# NTP server (this device)
dhcp-option=42,${STATIC_IP}

# DNS (forward to public DNS)
server=8.8.8.8
server=8.8.4.4

# Local domain
domain=mediamux.local
local=/mediamux.local/

# Don't read /etc/resolv.conf
no-resolv

# Log queries (useful for debugging)
#log-queries

# DHCP authoritative mode
dhcp-authoritative
EOF
log_ok

#------------------------------------------------------------------------------
# Step 4: Create minidlna configuration
#------------------------------------------------------------------------------
log_step "[4/11] Creating minidlna configuration..."
cat > /etc/minidlna-selfhosted.conf << EOF
# Media-Mux Self-Hosted DLNA Configuration
# This file is managed by setup-selfhosted.sh

# Network interface
network_interface=${ETH_INTERFACE}

# Port
port=${DLNA_PORT}

# Media directory (USB mount point)
media_dir=V,${USB_MOUNT_POINT}
media_dir=A,${USB_MOUNT_POINT}
media_dir=P,${USB_MOUNT_POINT}

# Friendly name (matches Kodi's pre-configured source)
friendly_name=dlnaserver

# Fixed UUID matching pocket router's minidlna config
# This allows the same sources.xml to work with both self-hosted and pocket router DLNA
uuid=dlnaserver

# Database location
db_dir=/var/lib/minidlna

# Log directory
log_dir=/var/log

# Automatic discovery of new files
inotify=yes

# Strictly adhere to DLNA standards
strict_dlna=no

# Presentation URL
presentation_url=http://${STATIC_IP}:${DLNA_PORT}/

# Model name and number
model_name=Media-Mux
model_number=1
EOF
log_ok

#------------------------------------------------------------------------------
# Step 5: Create USB mount point
#------------------------------------------------------------------------------
log_step "[5/11] Creating USB mount point..."
mkdir -p "${USB_MOUNT_POINT}"
log_ok

#------------------------------------------------------------------------------
# Step 6: Create chrony configurations
#------------------------------------------------------------------------------
log_step "[6/11] Creating chrony configurations..."

# Master mode config (NTP server)
cat > /etc/chrony/chrony-master.conf << EOF
# Media-Mux Chrony Master Configuration (NTP Server)
# This file is managed by setup-selfhosted.sh

# Use public NTP servers as upstream (when internet is available)
pool pool.ntp.org iburst

# Allow NTP clients on the local network
allow 192.168.8.0/24

# Serve time even if not synchronized to an upstream source
local stratum 10

# Record the rate at which the system clock gains/loses time
driftfile /var/lib/chrony/drift

# Log files location
logdir /var/log/chrony

# Step clock if offset is larger than 1 second (faster initial sync)
makestep 1 3
EOF

# Slave mode config (NTP client)
cat > /etc/chrony/chrony-slave.conf << EOF
# Media-Mux Chrony Slave Configuration (NTP Client)
# This file is managed by setup-selfhosted.sh

# Use the master Pi as NTP server
server ${STATIC_IP} iburst prefer

# Fallback to public NTP if master is unreachable
pool pool.ntp.org iburst

# Record the rate at which the system clock gains/loses time
driftfile /var/lib/chrony/drift

# Log files location
logdir /var/log/chrony

# Step clock if offset is larger than 1 second (faster initial sync)
makestep 1 3
EOF

log_ok

#------------------------------------------------------------------------------
# Step 7: Create boot script
#------------------------------------------------------------------------------
log_step "[7/11] Creating selfhosted boot script..."

cat > /home/pi/media-mux/media-mux-selfhosted-boot.sh << 'BOOTSCRIPT'
#!/bin/bash
#
# media-mux-selfhosted-boot.sh
# Runs at boot to detect USB and configure master/slave mode
#

LOG_FILE="/var/log/media-mux-selfhosted.log"
STATIC_IP="192.168.8.1"
NETMASK="24"
ETH_INTERFACE="eth0"
USB_MOUNT_POINT="/media/usb"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $1" | tee -a "$LOG_FILE"
}

#------------------------------------------------------------------------------
# Detect USB storage device
#------------------------------------------------------------------------------
detect_usb_storage() {
    # Look for USB block devices (exclude boot SD card)
    for dev in /sys/block/sd*; do
        if [ -d "$dev" ]; then
            devname=$(basename "$dev")
            # Check if it's a USB device
            if readlink -f "$dev/device" | grep -q "usb"; then
                echo "/dev/${devname}"
                return 0
            fi
        fi
    done
    return 1
}

#------------------------------------------------------------------------------
# Mount USB storage
#------------------------------------------------------------------------------
mount_usb() {
    local device="$1"

    # Try to find a partition, otherwise use the device directly
    if [ -b "${device}1" ]; then
        device="${device}1"
    fi

    log "Mounting $device to $USB_MOUNT_POINT"

    # Create mount point
    mkdir -p "$USB_MOUNT_POINT"

    # Try to mount (support ntfs, vfat, ext4)
    if mount -o ro "$device" "$USB_MOUNT_POINT" 2>/dev/null; then
        log "USB mounted successfully (read-only)"
        return 0
    elif mount "$device" "$USB_MOUNT_POINT" 2>/dev/null; then
        log "USB mounted successfully"
        return 0
    else
        log "Failed to mount USB device"
        return 1
    fi
}

#------------------------------------------------------------------------------
# Configure master mode (static IP, DHCP, DLNA)
#------------------------------------------------------------------------------
configure_master_mode() {
    log "=== MASTER MODE ==="

    # Stop NetworkManager and dhcpcd from managing eth0
    log "Stopping network managers for $ETH_INTERFACE..."
    systemctl stop NetworkManager 2>/dev/null || true
    systemctl stop dhcpcd 2>/dev/null || true

    # Release any DHCP lease
    dhclient -r "$ETH_INTERFACE" 2>/dev/null || true

    # Kill any dhclient processes for this interface
    pkill -f "dhclient.*$ETH_INTERFACE" 2>/dev/null || true

    # Configure static IP
    log "Setting static IP: $STATIC_IP/$NETMASK on $ETH_INTERFACE"
    ip addr flush dev "$ETH_INTERFACE"
    ip addr add "${STATIC_IP}/${NETMASK}" dev "$ETH_INTERFACE"
    ip link set "$ETH_INTERFACE" up

    # Wait for interface to be ready
    sleep 2

    # Start dnsmasq (DHCP/DNS)
    log "Starting dnsmasq..."
    systemctl start dnsmasq
    if systemctl is-active --quiet dnsmasq; then
        log "dnsmasq started successfully"
    else
        log "ERROR: dnsmasq failed to start"
    fi

    # Ensure minidlna directories exist with correct permissions
    log "Preparing minidlna directories..."
    mkdir -p /var/lib/minidlna
    mkdir -p /run/minidlna
    chown -R minidlna:minidlna /var/lib/minidlna 2>/dev/null || true
    chown -R minidlna:minidlna /run/minidlna 2>/dev/null || true

    # Start minidlna with our config
    log "Starting minidlna..."
    minidlnad -f /etc/minidlna-selfhosted.conf
    sleep 3
    if pgrep -f minidlnad > /dev/null; then
        log "minidlna started successfully (PID: $(pgrep -f minidlnad))"
    else
        log "minidlna first attempt failed, retrying..."
        sleep 2
        minidlnad -f /etc/minidlna-selfhosted.conf
        sleep 2
        if pgrep -f minidlnad > /dev/null; then
            log "minidlna started successfully on retry (PID: $(pgrep -f minidlnad))"
        else
            log "ERROR: minidlna failed to start"
        fi
    fi

    # Start chrony as NTP server
    log "Starting chrony (NTP server)..."
    chronyd -f /etc/chrony/chrony-master.conf
    sleep 2
    if pgrep -f chronyd > /dev/null; then
        log "chrony started successfully (PID: $(pgrep -f chronyd))"
    else
        log "ERROR: chrony failed to start"
    fi

    log "Master mode configured successfully"
    log "  Static IP: $STATIC_IP"
    log "  DHCP range: 192.168.8.100-200"
    log "  DLNA: http://${STATIC_IP}:8200/"
    log "  NTP: serving time to clients"
    log "  USB media: $USB_MOUNT_POINT"
}

#------------------------------------------------------------------------------
# Configure slave mode (DHCP client)
#------------------------------------------------------------------------------
configure_slave_mode() {
    log "=== SLAVE MODE ==="
    log "No USB storage detected - running as DHCP client"

    # Let the system's default network manager handle DHCP
    # Just ensure NetworkManager or dhcpcd is running
    if systemctl is-enabled NetworkManager 2>/dev/null; then
        log "NetworkManager will handle DHCP"
        systemctl start NetworkManager 2>/dev/null || true
    elif systemctl is-enabled dhcpcd 2>/dev/null; then
        log "dhcpcd will handle DHCP"
        systemctl start dhcpcd 2>/dev/null || true
    else
        # Fallback to manual dhclient
        log "Using dhclient for DHCP"
        dhclient "$ETH_INTERFACE" 2>/dev/null || true
    fi

    log "Waiting for network..."
    sleep 5

    # Start chrony as NTP client (sync from master)
    log "Starting chrony (NTP client)..."
    chronyd -f /etc/chrony/chrony-slave.conf
    sleep 2
    if pgrep -f chronyd > /dev/null; then
        log "chrony started successfully (PID: $(pgrep -f chronyd))"
    else
        log "WARNING: chrony failed to start"
    fi
}

#------------------------------------------------------------------------------
# Main
#------------------------------------------------------------------------------
log "========================================"
log "Media-Mux Self-Hosted Boot"
log "========================================"

# Wait for system to settle (USB devices to be recognized)
log "Waiting for USB devices to settle..."
sleep 3

# Detect USB storage (with retry)
USB_DEVICE=""
for i in 1 2 3; do
    USB_DEVICE=$(detect_usb_storage)
    if [ -n "$USB_DEVICE" ]; then
        break
    fi
    log "USB detection attempt $i - not found, retrying..."
    sleep 2
done

if [ -n "$USB_DEVICE" ]; then
    log "USB storage detected: $USB_DEVICE"

    if mount_usb "$USB_DEVICE"; then
        configure_master_mode
    else
        log "USB mount failed - falling back to slave mode"
        configure_slave_mode
    fi
else
    log "No USB storage detected"
    configure_slave_mode
fi

log "Boot script complete"
BOOTSCRIPT

chmod +x /home/pi/media-mux/media-mux-selfhosted-boot.sh
chown pi:pi /home/pi/media-mux/media-mux-selfhosted-boot.sh
log_ok

#------------------------------------------------------------------------------
# Step 8: Create systemd service
#------------------------------------------------------------------------------
log_step "[8/11] Creating systemd service..."
cat > /etc/systemd/system/media-mux-selfhosted.service << EOF
[Unit]
Description=Media-Mux Self-Hosted Boot
After=local-fs.target
Before=network-online.target
Wants=local-fs.target

[Service]
Type=oneshot
ExecStart=/home/pi/media-mux/media-mux-selfhosted-boot.sh
RemainAfterExit=yes
TimeoutStartSec=60
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable media-mux-selfhosted.service
log_ok

#------------------------------------------------------------------------------
# Step 9: Install Kodi Media-Mux Sync add-on
#------------------------------------------------------------------------------
log_step "[9/11] Installing Kodi Media-Mux Sync add-on..."

KODI_USER_HOME="/home/pi"
KODI_ADDONS_DIR="${KODI_USER_HOME}/.kodi/addons"
KODI_USERDATA_DIR="${KODI_USER_HOME}/.kodi/userdata"
ADDON_SRC_DIR="${SCRIPT_DIR}/kodi-addon/service.mediamux.sync"

# Create Kodi directories if they don't exist
mkdir -p "${KODI_ADDONS_DIR}"
mkdir -p "${KODI_USERDATA_DIR}/keymaps"

# Copy the add-on
if [ -d "${ADDON_SRC_DIR}" ]; then
    rm -rf "${KODI_ADDONS_DIR}/service.mediamux.sync"
    cp -r "${ADDON_SRC_DIR}" "${KODI_ADDONS_DIR}/"
    # Remove VideoOSD.xml and icons from add-on dir (they go elsewhere)
    rm -f "${KODI_ADDONS_DIR}/service.mediamux.sync/VideoOSD.xml"
    rm -f "${KODI_ADDONS_DIR}/service.mediamux.sync/start-sync-playback.png"
    rm -f "${KODI_ADDONS_DIR}/service.mediamux.sync/stop-sync-playback.png"
    chown -R pi:pi "${KODI_ADDONS_DIR}/service.mediamux.sync"
    log_ok
else
    log_skip "Add-on source not found at ${ADDON_SRC_DIR}"
fi

#------------------------------------------------------------------------------
# Step 10: Patch Kodi Estuary skin with Sync button
#------------------------------------------------------------------------------
log_step "[10/11] Patching Kodi skin with Sync button..."

SYSTEM_SKIN_DIR="/usr/share/kodi/addons/skin.estuary"
USER_SKIN_DIR="${KODI_ADDONS_DIR}/skin.estuary"

# Copy Estuary skin to user directory if not already there
if [ -d "${SYSTEM_SKIN_DIR}" ] && [ ! -d "${USER_SKIN_DIR}" ]; then
    cp -r "${SYSTEM_SKIN_DIR}" "${USER_SKIN_DIR}"
fi

if [ -d "${USER_SKIN_DIR}" ]; then
    # Copy custom icons (sync and stop)
    mkdir -p "${USER_SKIN_DIR}/media/osd/fullscreen/buttons"
    if [ -f "${ADDON_SRC_DIR}/start-sync-playback.png" ]; then
        cp "${ADDON_SRC_DIR}/start-sync-playback.png" "${USER_SKIN_DIR}/media/osd/fullscreen/buttons/"
    fi
    if [ -f "${ADDON_SRC_DIR}/stop-sync-playback.png" ]; then
        cp "${ADDON_SRC_DIR}/stop-sync-playback.png" "${USER_SKIN_DIR}/media/osd/fullscreen/buttons/"
    fi

    # Copy patched VideoOSD.xml
    if [ -f "${ADDON_SRC_DIR}/VideoOSD.xml" ]; then
        cp "${ADDON_SRC_DIR}/VideoOSD.xml" "${USER_SKIN_DIR}/xml/VideoOSD.xml"
    fi

    # Copy keymap
    if [ -f "${ADDON_SRC_DIR}/resources/keymaps/mediamux.xml" ]; then
        cp "${ADDON_SRC_DIR}/resources/keymaps/mediamux.xml" "${KODI_USERDATA_DIR}/keymaps/"
    fi

    chown -R pi:pi "${USER_SKIN_DIR}"
    chown -R pi:pi "${KODI_USERDATA_DIR}/keymaps"
    log_ok
else
    log_skip "Kodi skin not found at ${USER_SKIN_DIR}"
fi

#------------------------------------------------------------------------------
# Step 11: Configure Kodi addons (auto-enable our addon, disable version check)
#------------------------------------------------------------------------------
log_step "[11/11] Configuring Kodi addons database..."

KODI_DB_DIR="${KODI_USER_HOME}/.kodi/userdata/Database"
mkdir -p "${KODI_DB_DIR}"

# Find existing Addons database or determine version to create
# Kodi 20 uses Addons33.db, Kodi 21 uses Addons34.db
ADDONS_DB=$(find "${KODI_DB_DIR}" -name "Addons*.db" 2>/dev/null | head -1)

if [ -z "${ADDONS_DB}" ]; then
    # No database exists yet - create Addons33.db (Kodi 20 Nexus)
    ADDONS_DB="${KODI_DB_DIR}/Addons33.db"
fi

# Create/update the addons database
# Only modify the installed table - don't touch version table (Kodi manages it)
sqlite3 "${ADDONS_DB}" <<'SQLEOF'
-- Create installed table if not exists (matches Kodi schema)
CREATE TABLE IF NOT EXISTS installed (
    id INTEGER PRIMARY KEY,
    addonID TEXT UNIQUE,
    enabled INTEGER DEFAULT 1,
    installDate TEXT,
    lastUpdated TEXT,
    lastUsed TEXT,
    origin TEXT DEFAULT ''
);

-- Enable our Media-Mux sync addon (no startup prompt)
INSERT OR REPLACE INTO installed (addonID, enabled, installDate, origin)
VALUES ('service.mediamux.sync', 1, datetime('now'), 'user');

-- Disable version check addon (no "new version available" popup)
INSERT OR REPLACE INTO installed (addonID, enabled, installDate, origin)
VALUES ('service.xbmc.versioncheck', 0, datetime('now'), 'system');
SQLEOF

chown pi:pi "${ADDONS_DB}"
chown -R pi:pi "${KODI_DB_DIR}"
log_ok

#------------------------------------------------------------------------------
# Summary
#------------------------------------------------------------------------------
echo ""
log "=============================================="
log "  Setup Complete!"
log "=============================================="
echo ""
log "On next boot:"
log "  - If USB storage is attached → Master mode"
log "    - Static IP: ${STATIC_IP}"
log "    - DHCP: ${DHCP_RANGE_START}-${DHCP_RANGE_END}"
log "    - DLNA: http://${STATIC_IP}:${DLNA_PORT}/"
log "    - NTP: serving time to clients"
log ""
log "  - If no USB storage → Slave mode"
log "    - DHCP client"
log "    - NTP client (syncs from master)"
echo ""
log "USB mount point: ${USB_MOUNT_POINT}"
log "Log file: ${LOG_FILE}"
echo ""
log "Kodi Sync Add-on:"
log "  - OSD button: Tap screen during playback → 'Sync' button"
log "  - Keyboard shortcut: Press 'S' during video"
log "  - Programs menu: Programs → Add-ons → Media-Mux Sync"
echo ""
log "To test now (without reboot):"
log "  sudo /home/pi/media-mux/media-mux-selfhosted-boot.sh"
echo ""
log "To check status after boot:"
log "  journalctl -u media-mux-selfhosted.service"
log "  cat ${LOG_FILE}"
echo ""
