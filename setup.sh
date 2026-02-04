#!/bin/sh
#
# Media-Mux Setup Script
# Sets up a Raspberry Pi as a media-mux Kodi player (master or slave)
#
# Usage: sudo ./setup.sh -n <number> [OPTIONS]
#   -n <number>   Pi sequence number (1 = master, 2+ = slave)
#   --no-reboot   Skip automatic reboot after setup
#   --help        Show this help message

#------------------------------------------------------------------------------
# Configuration
#------------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
INSTALL_DIR="/home/pi/media-mux"
BACKUP_DIR="/home/pi/media-mux-backup"
LOG_FILE="/var/log/media-mux-setup.log"

#------------------------------------------------------------------------------
# Parse command line arguments
#------------------------------------------------------------------------------
SLAVE_NUM="none"
NO_REBOOT=0

show_help() {
	echo "Media-Mux Setup Script"
	echo ""
	echo "Usage: sudo $0 -n <number> [OPTIONS]"
	echo ""
	echo "Arguments:"
	echo "  -n <number>   Pi sequence number (1 = master, 2+ = slave)"
	echo ""
	echo "Options:"
	echo "  --no-reboot   Skip automatic reboot after setup"
	echo "  --help        Show this help message"
	echo ""
	echo "Examples:"
	echo "  sudo $0 -n 1              # Setup as master (media-mux-0001)"
	echo "  sudo $0 -n 2              # Setup as slave (media-mux-0002)"
	echo "  sudo $0 -n 3 --no-reboot  # Setup as slave, don't reboot"
	exit 0
}

# Parse options
while [ $# -gt 0 ]; do
	case "$1" in
		-n)
			shift
			SLAVE_NUM="$1"
			;;
		--no-reboot)
			NO_REBOOT=1
			;;
		--help|-h)
			show_help
			;;
		*)
			echo "Unknown option: $1"
			echo "Use --help for usage information"
			exit 1
			;;
	esac
	shift
done

#------------------------------------------------------------------------------
# Logging functions
#------------------------------------------------------------------------------
log() {
	echo "$1"
	echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >> "$LOG_FILE"
}

log_step() {
	printf "%-55s " "$1"
}

log_ok() {
	echo "[OK]"
	echo "$(date '+%Y-%m-%d %H:%M:%S') [OK] $1" >> "$LOG_FILE"
}

log_fail() {
	echo "[FAIL]"
	echo "$(date '+%Y-%m-%d %H:%M:%S') [FAIL] $1" >> "$LOG_FILE"
}

log_skip() {
	echo "[SKIP]"
	echo "$(date '+%Y-%m-%d %H:%M:%S') [SKIP] $1" >> "$LOG_FILE"
}

#------------------------------------------------------------------------------
# Error handling
#------------------------------------------------------------------------------
fail_and_exit() {
	log_fail "$1"
	log "Setup failed! Check $LOG_FILE for details."
	exit 1
}

#------------------------------------------------------------------------------
# Validation
#------------------------------------------------------------------------------
if [ "$SLAVE_NUM" = "none" ]; then
	echo "Error: Missing required argument -n <number>"
	echo "Use --help for usage information"
	exit 1
fi

if [ $(id -u) -ne 0 ]; then
	echo "Error: Please run setup as root"
	echo "Usage: sudo $0 -n $SLAVE_NUM"
	exit 1
fi

# Validate that SLAVE_NUM is a number
case "$SLAVE_NUM" in
	''|*[!0-9]*)
		echo "Error: '$SLAVE_NUM' is not a valid number"
		exit 1
		;;
	*)
		NUM=$(printf "%04d" "$SLAVE_NUM")
		;;
esac

# Verify we're in the correct directory
if [ ! -f "$SCRIPT_DIR/media-mux-controller.c" ]; then
	echo "Error: Script must be run from the media-mux directory"
	echo "Current directory: $SCRIPT_DIR"
	exit 1
fi

#------------------------------------------------------------------------------
# Setup starts here
#------------------------------------------------------------------------------
log "=============================================="
log "Media-Mux Setup - Device: media-mux-$NUM"
log "=============================================="
log "Install directory: $INSTALL_DIR"
log "Log file: $LOG_FILE"
echo ""

# Create backup directory
mkdir -p "$BACKUP_DIR"

#------------------------------------------------------------------------------
# Step 1: Create autoplay symlink
#------------------------------------------------------------------------------
log_step "Setting up auto-startup player..."
rm -f "$SCRIPT_DIR/media-mux-autoplay.sh" 2>/dev/null
if [ "$NUM" = "0001" ]; then
	ln -s media-mux-autoplay-master.sh "$SCRIPT_DIR/media-mux-autoplay.sh"
else
	ln -s media-mux-autoplay-slave.sh "$SCRIPT_DIR/media-mux-autoplay.sh"
fi
if [ $? -eq 0 ]; then
	log_ok "autoplay symlink"
else
	fail_and_exit "Failed to create autoplay symlink"
fi

#------------------------------------------------------------------------------
# Step 2: Install dependencies
#------------------------------------------------------------------------------
log_step "Installing dependencies (this may take a while)..."
DEBIAN_FRONTEND=noninteractive apt-get update -qq 2>&1 >> "$LOG_FILE"
DEBIAN_FRONTEND=noninteractive apt-get install -qq -y \
	avahi-daemon avahi-discover libnss-mdns avahi-utils \
	kodi jq nodejs npm 2>&1 >> "$LOG_FILE"
if [ $? -eq 0 ]; then
	log_ok "dependencies"
else
	fail_and_exit "Failed to install dependencies"
fi

#------------------------------------------------------------------------------
# Step 3: Configure avahi-publish (idempotent - regenerate from scratch)
#------------------------------------------------------------------------------
log_step "Configuring avahi-publish service..."
cat > "$SCRIPT_DIR/avahi-publish-media-mux.sh" << EOF
#!/bin/sh
MY_ID_STRING="media-mux-$NUM"
MY_ID_PORT=80
MY_ID_SERVICE="_http._tcp"
MY_ID_HW=\$(ifconfig |grep -A1 eth0 |grep inet | awk '{print \$2}')
avahi-publish-service -s "\$MY_ID_STRING [\$MY_ID_HW]" \$MY_ID_SERVICE \$MY_ID_PORT
EOF
chmod +x "$SCRIPT_DIR/avahi-publish-media-mux.sh"
if [ $? -eq 0 ]; then
	log_ok "avahi-publish"
else
	fail_and_exit "Failed to configure avahi-publish"
fi

#------------------------------------------------------------------------------
# Step 4: Set hostname (with backup)
#------------------------------------------------------------------------------
log_step "Setting hostname to media-mux-$NUM..."
if [ -f /etc/hostname ]; then
	cp /etc/hostname "$BACKUP_DIR/hostname.backup" 2>/dev/null
fi
echo "media-mux-$NUM" > /etc/hostname
if [ $? -eq 0 ]; then
	log_ok "hostname"
else
	fail_and_exit "Failed to set hostname"
fi

#------------------------------------------------------------------------------
# Step 5: Setup rc.local (with backup)
#------------------------------------------------------------------------------
log_step "Configuring rc.local startup script..."
if [ -f /etc/rc.local ]; then
	cp /etc/rc.local "$BACKUP_DIR/rc.local.backup" 2>/dev/null
fi
if [ "$NUM" = "0001" ]; then
	cp "$SCRIPT_DIR/rc.local.master" /etc/rc.local
else
	cp "$SCRIPT_DIR/rc.local" /etc/
fi
if [ $? -eq 0 ]; then
	log_ok "rc.local"
else
	fail_and_exit "Failed to configure rc.local"
fi

#------------------------------------------------------------------------------
# Step 6: Compile media-mux-controller
#------------------------------------------------------------------------------
log_step "Compiling media-mux-controller..."
gcc "$SCRIPT_DIR/media-mux-controller.c" -o "$SCRIPT_DIR/media-mux-controller" 2>&1 >> "$LOG_FILE"
if [ $? -eq 0 ]; then
	log_ok "media-mux-controller"
else
	fail_and_exit "Failed to compile media-mux-controller"
fi

#------------------------------------------------------------------------------
# Step 7: Setup Kodi configuration
#------------------------------------------------------------------------------
log_step "Configuring Kodi settings..."
runuser -l pi -c 'mkdir -p /home/pi/.kodi/userdata' 2>&1 >> "$LOG_FILE"
runuser -l pi -c "cp $SCRIPT_DIR/sources.xml /home/pi/.kodi/userdata/" 2>&1 >> "$LOG_FILE"
runuser -l pi -c "cp $SCRIPT_DIR/guisettings.xml /home/pi/.kodi/userdata/" 2>&1 >> "$LOG_FILE"
if [ -f "$SCRIPT_DIR/wf-panel-pi.ini" ]; then
	runuser -l pi -c "mkdir -p /home/pi/.config" 2>&1 >> "$LOG_FILE"
	runuser -l pi -c "cp $SCRIPT_DIR/wf-panel-pi.ini /home/pi/.config/" 2>&1 >> "$LOG_FILE"
fi
if [ $? -eq 0 ]; then
	log_ok "Kodi config"
else
	log_fail "Kodi config (non-fatal)"
fi

#------------------------------------------------------------------------------
# Step 8: Initialize kodisync submodule and install dependencies
#------------------------------------------------------------------------------
log_step "Setting up kodisync..."
if [ ! -d "$SCRIPT_DIR/kodisync" ] || [ ! -f "$SCRIPT_DIR/kodisync/package.json" ]; then
	log_skip "kodisync directory not found or incomplete"
	log "  Note: Run 'git submodule update --init' to initialize kodisync"
else
	runuser -l pi -c "cd $SCRIPT_DIR/kodisync && npm --silent install" 2>&1 >> "$LOG_FILE"
	if [ $? -eq 0 ]; then
		log_ok "kodisync"
	else
		log_fail "kodisync npm install (non-fatal)"
	fi
fi

#------------------------------------------------------------------------------
# Step 9: Sync filesystem
#------------------------------------------------------------------------------
log_step "Syncing filesystem..."
sync
log_ok "sync"

#------------------------------------------------------------------------------
# Complete
#------------------------------------------------------------------------------
echo ""
log "=============================================="
log "Setup completed successfully!"
log "=============================================="
log "Device configured as: media-mux-$NUM"
if [ "$NUM" = "0001" ]; then
	log "Role: MASTER"
else
	log "Role: SLAVE"
fi
log "Backup location: $BACKUP_DIR"
log "Log file: $LOG_FILE"

if [ $NO_REBOOT -eq 1 ]; then
	echo ""
	log "Reboot skipped (--no-reboot). Please reboot manually to apply changes."
else
	echo ""
	log "Rebooting in 5 seconds... (Ctrl+C to cancel)"
	sleep 5
	reboot
fi
