#!/bin/sh

#This script is used for synchronizing all the kodi-players in the network(media-mux-*) using kodisync nodejs script(https://github.com/tremby/kodisync)
#
# Improved version with:
# - Polling instead of fixed sleeps
# - Error checking and retry logic
# - Parallel command execution
# - Player readiness verification
#
# Usage: media-mux-sync-kodi-players.sh [OPTIONS]
#   --master=<hostname>  Master Kodi device (default: media-mux-0001)
#   --debuglog           Enable verbose debug output
#   --help               Show this help message

#------------------------------------------------------------------------------
# Default configuration
#------------------------------------------------------------------------------
FINAL_RES=0
MASTER_HOST="media-mux-0001"
DEBUG_LOG=0
KODI_PORT="8888"
CURL_TIMEOUT=5
MAX_RETRIES=3
POLL_INTERVAL=0.5
MAX_WAIT_SECONDS=15

#------------------------------------------------------------------------------
# Parse command line arguments
#------------------------------------------------------------------------------
show_help() {
	echo "Usage: $0 [OPTIONS]"
	echo ""
	echo "Synchronize playback across all media-mux Kodi players on the network."
	echo ""
	echo "Options:"
	echo "  --master=<hostname>  Master Kodi device to sync from (default: media-mux-0001)"
	echo "  --debuglog           Enable verbose debug output"
	echo "  --help               Show this help message"
	echo ""
	echo "Examples:"
	echo "  $0                           # Use default master (media-mux-0001)"
	echo "  $0 --master=media-mux-0002   # Use media-mux-0002 as master"
	echo "  $0 --debuglog                # Enable debug output"
	echo "  $0 --master=192.168.1.100 --debuglog"
	exit 0
}

for arg in "$@"; do
	case $arg in
		--master=*)
			MASTER_HOST="${arg#*=}"
			;;
		--debuglog)
			DEBUG_LOG=1
			;;
		--help|-h)
			show_help
			;;
		*)
			echo "Unknown option: $arg"
			echo "Use --help for usage information"
			exit 1
			;;
	esac
done

#------------------------------------------------------------------------------
# Logging functions
#------------------------------------------------------------------------------
# Always log to syslog
log() {
	logger -t "media-mux-sync" "$1"
}

# Debug output - only prints to console if --debuglog is enabled
debug() {
	if [ $DEBUG_LOG -eq 1 ]; then
		echo "[DEBUG] $1"
	fi
}

# Send JSON-RPC command with retry logic
# Usage: kodi_rpc <host> <json_payload> [retries]
kodi_rpc() {
	local host="$1"
	local payload="$2"
	local retries="${3:-$MAX_RETRIES}"
	local attempt=1
	local resp=""

	while [ $attempt -le $retries ]; do
		resp=$(curl -s --connect-timeout $CURL_TIMEOUT -m $((CURL_TIMEOUT * 2)) \
			-X POST -H "content-type:application/json" \
			"http://${host}:${KODI_PORT}/jsonrpc" \
			-d "$payload" 2>/dev/null)

		# Check if we got a valid JSON response with result
		if echo "$resp" | jq -e '.result' >/dev/null 2>&1; then
			# Only output JSON if debug mode is enabled
			if [ $DEBUG_LOG -eq 1 ]; then
				echo "$resp"
			fi
			# Store response for caller to use if needed
			LAST_RPC_RESPONSE="$resp"
			return 0
		fi

		attempt=$((attempt + 1))
		[ $attempt -le $retries ] && sleep 0.3
	done

	log "ERROR: Failed to communicate with $host after $retries attempts"
	debug "Failed request to $host: $payload"
	return 1
}

# Check if a player has a file loaded and is ready (playing or paused)
# Returns 0 if ready, 1 if not
player_is_ready() {
	local host="$1"

	kodi_rpc "$host" '{"jsonrpc":"2.0","method":"Player.GetProperties","params":{"playerid":1,"properties":["speed","time","totaltime"]},"id":1}' 1

	if [ $? -eq 0 ]; then
		# Check if totaltime > 0 (file is loaded)
		local total_hours total_mins total_secs
		total_hours=$(echo "$LAST_RPC_RESPONSE" | jq -r '.result.totaltime.hours // 0')
		total_mins=$(echo "$LAST_RPC_RESPONSE" | jq -r '.result.totaltime.minutes // 0')
		total_secs=$(echo "$LAST_RPC_RESPONSE" | jq -r '.result.totaltime.seconds // 0')

		if [ "$total_hours" != "null" ] && [ "$total_mins" != "null" ] && [ "$total_secs" != "null" ]; then
			local total=$((total_hours * 3600 + total_mins * 60 + total_secs))
			[ $total -gt 0 ] && return 0
		fi
	fi
	return 1
}

# Wait for player to be ready with timeout
wait_for_player_ready() {
	local host="$1"
	local max_wait="$2"
	local elapsed=0

	while [ $elapsed -lt $max_wait ]; do
		if player_is_ready "$host"; then
			return 0
		fi
		sleep $POLL_INTERVAL
		elapsed=$((elapsed + 1))
	done

	log "WARNING: Timeout waiting for $host to be ready"
	return 1
}

# Send command to multiple hosts in parallel
# Usage: parallel_rpc <payload> <host1> <host2> ...
parallel_rpc() {
	local payload="$1"
	shift
	local pids=""
	local host

	for host in "$@"; do
		kodi_rpc "$host" "$payload" &
		pids="$pids $!"
	done

	# Wait for all background jobs
	for pid in $pids; do
		wait $pid 2>/dev/null
	done
}

# Discover all media-mux devices on the network (excluding localhost)
discover_devices() {
	avahi-browse -art 2>/dev/null | \
		grep -A2 "IPv4 media-mux" | \
		grep address | \
		sort -u | \
		sed 's/   address = \[//' | \
		sed 's/\]//' | \
		grep -v "127.0.0.1"
}

#------------------------------------------------------------------------------
# MAIN SCRIPT
#------------------------------------------------------------------------------

log "Starting sync operation"
debug "Master host: $MASTER_HOST"

# Get what is currently being played on master-kodi player (use consistent host)
kodi_rpc "$MASTER_HOST" '{"jsonrpc":"2.0","method":"Player.GetItem","params":{"properties":["title","album","duration","file"],"playerid":1},"id":"VideoGetItem"}'
if [ $? -ne 0 ]; then
	log "ERROR: Cannot communicate with master $MASTER_HOST"
	exit 1
fi

TITLE=$(echo "$LAST_RPC_RESPONSE" | jq -r '.result.item.file')
if [ -z "${TITLE}" ] || [ "${TITLE}" = "null" ]; then
	log "Nothing is playing on master $MASTER_HOST"
	exit 0
fi
debug "Playing file: $TITLE"

# Get current progress from same master host (consistent source)
kodi_rpc "$MASTER_HOST" '{"jsonrpc":"2.0","method":"Player.GetProperties","params":{"playerid":1,"properties":["percentage","time"]},"id":1}'
if [ $? -ne 0 ]; then
	log "ERROR: Cannot get playback position from master"
	exit 1
fi

PERCENTAGE=$(echo "$LAST_RPC_RESPONSE" | jq '.result.percentage')
if [ -z "${PERCENTAGE}" ] || [ "${PERCENTAGE}" = "null" ]; then
	log "ERROR: Invalid percentage from master"
	exit 1
fi

log "Master playing: $TITLE at $PERCENTAGE%"
debug "Position: $PERCENTAGE%"

# Discover all slave devices once (cache the list)
debug "Discovering devices via avahi-browse..."
DEVICES=$(discover_devices)
if [ -z "$DEVICES" ]; then
	log "WARNING: No slave devices discovered"
	exit 0
fi

DEVICE_COUNT=$(echo "$DEVICES" | wc -w)
log "Discovered $DEVICE_COUNT slave device(s): $DEVICES"
debug "Device list: $DEVICES"

# Step 1: Stop all players in parallel
log "Stopping all players..."
parallel_rpc '{"jsonrpc":"2.0","id":"1","method":"Player.Stop","params":{"playerid":1}}' $DEVICES
sleep 0.5

# Step 2: Open the file on all players in parallel
log "Opening file on all players..."
OPEN_PAYLOAD=$(printf '{"jsonrpc":"2.0","id":"1","method":"Player.Open","params":{"item":{"file":"%s"}}}' "$TITLE")
parallel_rpc "$OPEN_PAYLOAD" $DEVICES

# Step 3: Wait for all players to be ready (polling instead of fixed sleep)
log "Waiting for all players to load file..."
ALL_READY=1
for device in $DEVICES; do
	if ! wait_for_player_ready "$device" $MAX_WAIT_SECONDS; then
		log "WARNING: Device $device not ready, continuing anyway"
		ALL_READY=0
	fi
done

if [ $ALL_READY -eq 1 ]; then
	log "All players ready"
else
	log "Proceeding with sync despite some players not ready"
fi

# Step 4: Build device list for kodisync and run it
TMP_DEVICES=""
for device in $DEVICES; do
	TMP_DEVICES="$TMP_DEVICES $device:$KODI_PORT"
done

log "Running kodisync to pause all players at same frame..."
debug "kodisync devices: $TMP_DEVICES"
KODISYNC_TIMEOUT=20
if [ $DEBUG_LOG -eq 1 ]; then
	node /home/pi/media-mux/kodisync/kodisync.js --once --timeout $KODISYNC_TIMEOUT $TMP_DEVICES
else
	node /home/pi/media-mux/kodisync/kodisync.js --once --timeout $KODISYNC_TIMEOUT $TMP_DEVICES >/dev/null 2>&1
fi
KODISYNC_EXIT=$?

if [ $KODISYNC_EXIT -ne 0 ]; then
	log "WARNING: kodisync exited with code $KODISYNC_EXIT"
fi
debug "kodisync exit code: $KODISYNC_EXIT"

# Step 5: Seek all players to master position in parallel
log "Seeking all players to $PERCENTAGE%..."
SEEK_PAYLOAD=$(printf '{"jsonrpc":"2.0","id":"1","method":"Player.Seek","params":{"playerid":1,"value":{"percentage":%s}}}' "$PERCENTAGE")
parallel_rpc "$SEEK_PAYLOAD" $DEVICES
sleep 0.3

# Step 6: Resume playback on all players simultaneously
# Use a tighter timing approach - prepare commands and fire together
log "Resuming playback on all players..."
PLAY_PAYLOAD='{"jsonrpc":"2.0","method":"Player.PlayPause","params":{"playerid":1},"id":1}'

# Fire all play commands as close together as possible
for device in $DEVICES; do
	curl -s --connect-timeout 2 -m 3 \
		-X POST -H "content-type:application/json" \
		"http://${device}:${KODI_PORT}/jsonrpc" \
		-d "$PLAY_PAYLOAD" >/dev/null 2>&1 &
done

# Wait for all background curl processes
wait

log "Sync operation completed"
debug "Sync finished successfully"
exit $FINAL_RES
