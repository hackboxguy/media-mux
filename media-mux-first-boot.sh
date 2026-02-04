#!/bin/sh
#
# media-mux-first-boot.sh
# First boot initialization for auto-negotiation mode
#
# This script runs on first boot to:
# 1. Generate a unique hostname from MAC address
# 2. Configure avahi-publish with the new hostname
# 3. Remove the first-boot marker
#
# Called from rc.local.auto on first boot only

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MARKER_FILE="$SCRIPT_DIR/.first-boot-pending"
LOG_FILE="/var/log/media-mux-setup.log"

log() {
	echo "$(date '+%Y-%m-%d %H:%M:%S') [first-boot] $1" >> "$LOG_FILE"
	echo "[first-boot] $1"
}

# Check if we're supposed to run
if [ ! -f "$MARKER_FILE" ]; then
	log "No first-boot marker found, skipping"
	exit 0
fi

log "Starting first-boot initialization..."

# Get MAC address from eth0 (or wlan0 as fallback)
MAC=""
if [ -f /sys/class/net/eth0/address ]; then
	MAC=$(cat /sys/class/net/eth0/address)
elif [ -f /sys/class/net/wlan0/address ]; then
	MAC=$(cat /sys/class/net/wlan0/address)
fi

if [ -z "$MAC" ]; then
	log "ERROR: Cannot determine MAC address"
	exit 1
fi

log "MAC address: $MAC"

# Extract last 4 hex characters (last 2 octets without colons)
# e.g., dc:a6:32:xx:yy:zz -> yyzz
MAC_SUFFIX=$(echo "$MAC" | sed 's/://g' | tail -c 5)

# Generate hostname
HOSTNAME="media-mux-${MAC_SUFFIX}"
log "Generated hostname: $HOSTNAME"

# Set hostname
echo "$HOSTNAME" > /etc/hostname
hostname "$HOSTNAME"

# Update /etc/hosts to include new hostname
if grep -q "127.0.1.1" /etc/hosts; then
	sed -i "s/127.0.1.1.*/127.0.1.1\t$HOSTNAME/" /etc/hosts
else
	echo "127.0.1.1\t$HOSTNAME" >> /etc/hosts
fi

# Regenerate avahi-publish script with the new hostname
cat > "$SCRIPT_DIR/avahi-publish-media-mux.sh" << EOF
#!/bin/sh
MY_ID_STRING="$HOSTNAME"
MY_ID_PORT=80
MY_ID_SERVICE="_http._tcp"
MY_ID_HW=\$(ifconfig |grep -A1 eth0 |grep inet | awk '{print \$2}')
avahi-publish-service -s "\$MY_ID_STRING [\$MY_ID_HW]" \$MY_ID_SERVICE \$MY_ID_PORT
EOF
chmod +x "$SCRIPT_DIR/avahi-publish-media-mux.sh"

log "Avahi-publish script updated"

# Remove first-boot marker
rm -f "$MARKER_FILE"
log "First-boot initialization complete"

# Note: We don't restart avahi-publish here as it will be started fresh by rc.local
