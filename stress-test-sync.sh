#!/bin/sh
#
# Media-Mux Sync Stress Test Script
# Runs multiple sync iterations with random start positions and analyzes results
#
# Usage: ./stress-test-sync.sh --master=<host> --media=<url> [OPTIONS]
#   --master=<host>    Master Kodi device hostname
#   --media=<url>      Media file URL to play
#   --loopcount=<n>    Number of iterations (default: 20)
#   --failstop=yes/no  Stop on first failure (default: no)
#   --help             Show this help message

#------------------------------------------------------------------------------
# Configuration
#------------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SYNC_SCRIPT="$SCRIPT_DIR/media-mux-sync-kodi-players.sh"
KODI_PORT="8888"
CURL_TIMEOUT=5

# Default values
MASTER_HOST=""
MEDIA_URL=""
LOOP_COUNT=20
FAIL_STOP="no"

# Statistics
PASS_COUNT=0
WARN_COUNT=0
FAIL_COUNT=0
TOTAL_SPREAD=0
MAX_SPREAD=0

# Log file
LOG_DIR="$SCRIPT_DIR/stress-test-logs"
TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
LOG_FILE="$LOG_DIR/stress-test-$TIMESTAMP.log"

#------------------------------------------------------------------------------
# Parse command line arguments
#------------------------------------------------------------------------------
show_help() {
	echo "Media-Mux Sync Stress Test"
	echo ""
	echo "Usage: $0 --master=<host> --media=<url> [OPTIONS]"
	echo ""
	echo "Required:"
	echo "  --master=<host>    Master Kodi device hostname (e.g., media-mux-0001)"
	echo "  --media=<url>      Media file URL to play"
	echo ""
	echo "Options:"
	echo "  --loopcount=<n>    Number of iterations (default: 20)"
	echo "  --failstop=yes/no  Stop on first failure (default: no)"
	echo "  --help             Show this help message"
	echo ""
	echo "Example:"
	echo "  $0 --master=media-mux-0001 --media=http://192.168.8.1:8200/MediaItems/66.mp4 --loopcount=20 --failstop=yes"
	exit 0
}

for arg in "$@"; do
	case $arg in
		--master=*)
			MASTER_HOST="${arg#*=}"
			;;
		--media=*)
			MEDIA_URL="${arg#*=}"
			;;
		--loopcount=*)
			LOOP_COUNT="${arg#*=}"
			;;
		--failstop=*)
			FAIL_STOP="${arg#*=}"
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

# Validate required arguments
if [ -z "$MASTER_HOST" ]; then
	echo "Error: --master is required"
	echo "Use --help for usage information"
	exit 1
fi

if [ -z "$MEDIA_URL" ]; then
	echo "Error: --media is required"
	echo "Use --help for usage information"
	exit 1
fi

#------------------------------------------------------------------------------
# Helper functions
#------------------------------------------------------------------------------

# Send JSON-RPC command to Kodi
kodi_rpc() {
	local host="$1"
	local payload="$2"
	curl -s --connect-timeout $CURL_TIMEOUT -m $((CURL_TIMEOUT * 2)) \
		-X POST -H "content-type:application/json" \
		"http://${host}:${KODI_PORT}/jsonrpc" \
		-d "$payload" 2>/dev/null
}

# Discover all media-mux devices
discover_devices() {
	avahi-browse -art 2>/dev/null | \
		grep -A2 "IPv4 media-mux" | \
		grep address | \
		sort -u | \
		sed 's/   address = \[//' | \
		sed 's/\]//' | \
		grep -v "127.0.0.1"
}

# Generate random percentage between 5 and 50
random_position() {
	# Use awk for better random number generation
	awk -v seed="$RANDOM$(date +%N)" 'BEGIN {
		srand(seed)
		printf "%.1f", 5 + rand() * 45
	}'
}

# Log to both console and file
log() {
	echo "$1"
	echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >> "$LOG_FILE"
}

# Log to file only
log_file() {
	echo "$(date '+%Y-%m-%d %H:%M:%S') $1" >> "$LOG_FILE"
}

# Print colored status
print_status() {
	local iteration="$1"
	local total="$2"
	local status="$3"
	local spread="$4"
	local details="$5"

	case "$status" in
		PASS)
			printf "[%2d/%2d] \033[32mPASS\033[0m - spread: %.4f%% %s\n" "$iteration" "$total" "$spread" "$details"
			;;
		WARN)
			printf "[%2d/%2d] \033[33mWARN\033[0m - spread: %.4f%% %s\n" "$iteration" "$total" "$spread" "$details"
			;;
		FAIL)
			printf "[%2d/%2d] \033[31mFAIL\033[0m - spread: %.4f%% %s\n" "$iteration" "$total" "$spread" "$details"
			;;
	esac
}

# Analyze sync output and determine result
# Returns: 0=PASS, 1=WARN, 2=FAIL
analyze_sync_output() {
	local output="$1"
	local status="PASS"
	local details=""

	# Extract final spread from output
	FINAL_SPREAD=$(echo "$output" | grep "Final position spread:" | tail -1 | sed 's/.*spread: \([0-9.]*\)%.*/\1/')

	# Check for kodisync exit code
	KODISYNC_EXIT=$(echo "$output" | grep "kodisync exit code:" | sed 's/.*exit code: //')

	# Check for re-sync attempts
	RESYNC_COUNT=$(echo "$output" | grep -c "Re-syncing all to")

	# Check for warnings
	WARNING_COUNT=$(echo "$output" | grep -c "WARNING:")

	# Check for errors
	ERROR_COUNT=$(echo "$output" | grep -c "ERROR:")

	# Determine status
	if [ -n "$ERROR_COUNT" ] && [ "$ERROR_COUNT" -gt 0 ]; then
		status="FAIL"
		details="(errors: $ERROR_COUNT)"
	elif [ -n "$KODISYNC_EXIT" ] && [ "$KODISYNC_EXIT" != "0" ]; then
		status="FAIL"
		details="(kodisync exit: $KODISYNC_EXIT)"
	elif [ -z "$FINAL_SPREAD" ]; then
		status="FAIL"
		FINAL_SPREAD="999"
		details="(no final spread found)"
	elif [ "$(awk "BEGIN {print ($FINAL_SPREAD > 0.2) ? 1 : 0}")" = "1" ]; then
		status="FAIL"
		details="(spread > 0.2%)"
	elif [ "$RESYNC_COUNT" -gt 0 ] || [ "$WARNING_COUNT" -gt 0 ]; then
		status="WARN"
		details="(resyncs: $RESYNC_COUNT, warnings: $WARNING_COUNT)"
	fi

	echo "$status|$FINAL_SPREAD|$details"
}

#------------------------------------------------------------------------------
# Pre-flight checks
#------------------------------------------------------------------------------

# Create log directory first (before any logging)
mkdir -p "$LOG_DIR"

log "=============================================="
log "Media-Mux Sync Stress Test"
log "=============================================="
log "Master: $MASTER_HOST"
log "Media: $MEDIA_URL"
log "Iterations: $LOOP_COUNT"
log "Fail stop: $FAIL_STOP"
log "Log file: $LOG_FILE"
log ""

# Check if sync script exists
if [ ! -f "$SYNC_SCRIPT" ]; then
	log "Error: Sync script not found: $SYNC_SCRIPT"
	exit 1
fi

# Discover devices
log "Discovering devices..."
DEVICES=$(discover_devices)
if [ -z "$DEVICES" ]; then
	log "Error: No media-mux devices found on network"
	exit 1
fi

DEVICE_COUNT=$(echo "$DEVICES" | wc -w)
log "Found $DEVICE_COUNT device(s): $(echo $DEVICES | tr '\n' ' ')"

# Check if master is reachable
log "Checking master connectivity..."
MASTER_CHECK=$(kodi_rpc "$MASTER_HOST" '{"jsonrpc":"2.0","method":"JSONRPC.Ping","id":1}')
if ! echo "$MASTER_CHECK" | grep -q '"result":"pong"'; then
	log "Error: Cannot connect to master $MASTER_HOST"
	exit 1
fi
log "Master $MASTER_HOST is reachable"

# Check all devices
log "Checking all device connectivity..."
for device in $DEVICES; do
	CHECK=$(kodi_rpc "$device" '{"jsonrpc":"2.0","method":"JSONRPC.Ping","id":1}')
	if echo "$CHECK" | grep -q '"result":"pong"'; then
		log "  $device: OK"
	else
		log "  $device: UNREACHABLE"
		log "Error: Device $device is not reachable"
		exit 1
	fi
done

log ""
log "All pre-flight checks passed. Starting stress test..."
log "=============================================="
log ""

#------------------------------------------------------------------------------
# Main stress test loop
#------------------------------------------------------------------------------
START_TIME=$(date +%s)

for i in $(seq 1 $LOOP_COUNT); do
	log_file "--- Iteration $i of $LOOP_COUNT ---"

	# Generate random start position (5-50%)
	RANDOM_POS=$(random_position)
	log_file "Random start position: $RANDOM_POS%"

	# Step 1: Open file on master and seek to random position
	log_file "Opening file on master at $RANDOM_POS%..."

	# Stop any current playback
	kodi_rpc "$MASTER_HOST" '{"jsonrpc":"2.0","id":"1","method":"Player.Stop","params":{"playerid":1}}' >/dev/null 2>&1
	sleep 0.5

	# Open the file
	OPEN_PAYLOAD=$(printf '{"jsonrpc":"2.0","id":"1","method":"Player.Open","params":{"item":{"file":"%s"}}}' "$MEDIA_URL")
	kodi_rpc "$MASTER_HOST" "$OPEN_PAYLOAD" >/dev/null 2>&1

	# Wait for file to load
	sleep 2

	# Seek to random position
	SEEK_PAYLOAD=$(printf '{"jsonrpc":"2.0","id":"1","method":"Player.Seek","params":{"playerid":1,"value":{"percentage":%s}}}' "$RANDOM_POS")
	kodi_rpc "$MASTER_HOST" "$SEEK_PAYLOAD" >/dev/null 2>&1
	sleep 1

	# Step 2: Run sync script and capture output
	log_file "Running sync script..."
	SYNC_OUTPUT=$("$SYNC_SCRIPT" --master="$MASTER_HOST" --debuglog 2>&1)
	SYNC_EXIT=$?

	# Log full output to file
	echo "$SYNC_OUTPUT" >> "$LOG_FILE"

	# Step 3: Analyze results
	RESULT=$(analyze_sync_output "$SYNC_OUTPUT")
	STATUS=$(echo "$RESULT" | cut -d'|' -f1)
	SPREAD=$(echo "$RESULT" | cut -d'|' -f2)
	DETAILS=$(echo "$RESULT" | cut -d'|' -f3)

	# Update statistics
	case "$STATUS" in
		PASS)
			PASS_COUNT=$((PASS_COUNT + 1))
			;;
		WARN)
			WARN_COUNT=$((WARN_COUNT + 1))
			;;
		FAIL)
			FAIL_COUNT=$((FAIL_COUNT + 1))
			;;
	esac

	# Update spread statistics (only for valid spreads)
	if [ "$SPREAD" != "999" ]; then
		TOTAL_SPREAD=$(awk "BEGIN {print $TOTAL_SPREAD + $SPREAD}")
		if [ "$(awk "BEGIN {print ($SPREAD > $MAX_SPREAD) ? 1 : 0}")" = "1" ]; then
			MAX_SPREAD="$SPREAD"
		fi
	fi

	# Print status
	print_status "$i" "$LOOP_COUNT" "$STATUS" "$SPREAD" "$DETAILS (start: $RANDOM_POS%)"
	log_file "Result: $STATUS - spread: $SPREAD% $DETAILS"

	# Check if we should stop on failure
	if [ "$FAIL_STOP" = "yes" ] && [ "$STATUS" = "FAIL" ]; then
		log ""
		log "Stopping due to --failstop=yes"
		break
	fi

	# Wait before next iteration to let playback run (unless it's the last one)
	if [ "$i" -lt "$LOOP_COUNT" ]; then
		log_file "Letting playback run for 10 seconds before next iteration..."
		sleep 10
	fi
done

#------------------------------------------------------------------------------
# Summary report
#------------------------------------------------------------------------------
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
COMPLETED=$((PASS_COUNT + WARN_COUNT + FAIL_COUNT))

# Calculate averages
if [ "$COMPLETED" -gt 0 ]; then
	AVG_SPREAD=$(awk "BEGIN {printf \"%.4f\", $TOTAL_SPREAD / $COMPLETED}")
	PASS_PCT=$(awk "BEGIN {printf \"%.1f\", $PASS_COUNT * 100 / $COMPLETED}")
	WARN_PCT=$(awk "BEGIN {printf \"%.1f\", $WARN_COUNT * 100 / $COMPLETED}")
	FAIL_PCT=$(awk "BEGIN {printf \"%.1f\", $FAIL_COUNT * 100 / $COMPLETED}")
else
	AVG_SPREAD="N/A"
	PASS_PCT="0"
	WARN_PCT="0"
	FAIL_PCT="0"
fi

log ""
log "=============================================="
log "STRESS TEST SUMMARY"
log "=============================================="
log "Total iterations: $COMPLETED / $LOOP_COUNT"
log "Duration: ${DURATION}s"
log ""
log "Results:"
printf "  \033[32mPASS\033[0m: %d (%s%%)\n" "$PASS_COUNT" "$PASS_PCT"
printf "  \033[33mWARN\033[0m: %d (%s%%)\n" "$WARN_COUNT" "$WARN_PCT"
printf "  \033[31mFAIL\033[0m: %d (%s%%)\n" "$FAIL_COUNT" "$FAIL_PCT"
log ""
log "Spread statistics:"
log "  Average: ${AVG_SPREAD}%"
log "  Maximum: ${MAX_SPREAD}%"
log ""
log "Full log: $LOG_FILE"
log "=============================================="

# Exit with error if any failures
if [ "$FAIL_COUNT" -gt 0 ]; then
	exit 1
fi
exit 0
