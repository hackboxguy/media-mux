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
#   --wait=<secs>      Wait time between iterations (default: 25)
#   --video-length=<s> Video duration in seconds for spread->ms conversion (default: 60)
#   --dso-ip=<ip>      Rigol oscilloscope IP (enables hardware sync measurement)
#   --dso-port=<port>  SCPI port (default: 5555)
#   --dso-config=<file> Apply scope config JSON on startup
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
ITER_WAIT=25
VIDEO_LENGTH=60

# DSO (oscilloscope) configuration
DSO_IP=""
DSO_PORT="5555"
DSO_CONFIG=""
DSO_ENABLED=0
DSO_INVALID="9.9000E+37"
DSO_WARN_MS=3
DSO_FAIL_MS=10

# Statistics
PASS_COUNT=0
WARN_COUNT=0
FAIL_COUNT=0
TOTAL_SPREAD=0
MAX_SPREAD=0

# DSO aggregate statistics
DSO_12_TOTAL_AVG=0
DSO_12_WORST_MAX=0
DSO_13_TOTAL_AVG=0
DSO_13_WORST_MAX=0
DSO_VALID_COUNT=0
DSO_TOTAL_QUALITY=0

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
	echo "  --wait=<secs>      Wait time between iterations for measurement (default: 25)"
	echo "  --video-length=<s> Video duration in seconds for spread->ms conversion (default: 60)"
	echo "  --help             Show this help message"
	echo ""
	echo "DSO Oscilloscope Options (optional - enables hardware sync measurement):"
	echo "  --dso-ip=<ip>      Rigol oscilloscope IP (enables DSO measurement)"
	echo "  --dso-port=<port>  SCPI port (default: 5555)"
	echo "  --dso-config=<file> Apply scope config JSON on startup"
	echo "  --dso-warn=<ms>    DSO avg delay threshold for WARN (default: 3)"
	echo "  --dso-fail=<ms>    DSO avg delay threshold for FAIL (default: 10)"
	echo ""
	echo "Example:"
	echo "  $0 --master=media-mux-0001 --media=http://192.168.8.1:8200/MediaItems/66.mp4 --loopcount=20 --failstop=yes"
	echo ""
	echo "Example with DSO:"
	echo "  $0 --master=192.168.8.1 --media=http://192.168.8.1:8200/MediaItems/31.mp4 --loopcount=5 --dso-ip=192.168.1.7 --wait=25"
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
		--wait=*)
			ITER_WAIT="${arg#*=}"
			;;
		--video-length=*)
			VIDEO_LENGTH="${arg#*=}"
			;;
		--dso-ip=*)
			DSO_IP="${arg#*=}"
			;;
		--dso-port=*)
			DSO_PORT="${arg#*=}"
			;;
		--dso-config=*)
			DSO_CONFIG="${arg#*=}"
			;;
		--dso-warn=*)
			DSO_WARN_MS="${arg#*=}"
			;;
		--dso-fail=*)
			DSO_FAIL_MS="${arg#*=}"
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

# Generate random percentage between 2 and 30
# (limited to 30% to ensure enough video remains for measurement window)
random_position() {
	awk -v seed="$RANDOM$(date +%N)" 'BEGIN {
		srand(seed)
		printf "%.1f", 2 + rand() * 28
	}'
}

#------------------------------------------------------------------------------
# DSO (oscilloscope) helper functions
#------------------------------------------------------------------------------

# SCPI query - returns trimmed response
scpi_q() {
	printf '%s\n' "$1" | timeout 3 nc -w 2 "$DSO_IP" "$DSO_PORT" 2>/dev/null | tr -d '\r\n'
}

# SCPI write - fire and forget
scpi_w() {
	printf '%s\n' "$1" | nc -N -w 1 "$DSO_IP" "$DSO_PORT" >/dev/null 2>&1
}

# Check if a SCPI value is valid (not empty, not the 9.9E+37 sentinel, not absurdly large)
scpi_val_valid() {
	local val="$1"
	[ -n "$val" ] && awk "BEGIN {v=$val+0; exit (v > 9e+30 || v < -9e+30) ? 1 : 0}" 2>/dev/null
}

# Format seconds to ms string, handles empty/invalid
fmt_ms() {
	local val="$1"
	if scpi_val_valid "$val"; then
		awk "BEGIN {printf \"%.3f\", $val * 1000}"
	else
		printf "N/A"
	fi
}

# Get absolute value of a number in ms (for worst-case tracking)
abs_ms() {
	local val="$1"
	if scpi_val_valid "$val"; then
		awk "BEGIN {v=$val*1000; if(v<0) v=-v; printf \"%.3f\", v}"
	else
		printf "0"
	fi
}

# Setup RRDelay measurements on scope for CH1->CH2 and CH1->CH3
dso_setup_measurements() {
	scpi_w ":MEAS:CLE"
	scpi_w ":MEAS:ITEM RRDelay,CHANnel1,CHANnel2"
	scpi_w ":MEAS:ITEM RRDelay,CHANnel1,CHANnel3"
	scpi_w ":MEAS:STAT:DISP ON"
	scpi_w ":MEAS:STAT:RES"
}

# Reset DSO statistics counters
dso_reset_stats() {
	scpi_w ":MEAS:STAT:RES"
}

# Read DSO statistics for both channel pairs
# Sets: DSO_12_CNT, DSO_12_AVG, DSO_12_MIN, DSO_12_MAX, DSO_12_DEV
#       DSO_13_CNT, DSO_13_AVG, DSO_13_MIN, DSO_13_MAX, DSO_13_DEV
dso_read_stats() {
	DSO_12_CNT=$(scpi_q ":MEAS:STAT:ITEM? CNT,RRDelay,CHANnel1,CHANnel2")
	DSO_12_MIN=$(scpi_q ":MEAS:STAT:ITEM? MIN,RRDelay,CHANnel1,CHANnel2")
	DSO_12_MAX=$(scpi_q ":MEAS:STAT:ITEM? MAX,RRDelay,CHANnel1,CHANnel2")
	DSO_12_AVG=$(scpi_q ":MEAS:STAT:ITEM? AVER,RRDelay,CHANnel1,CHANnel2")
	DSO_12_DEV=$(scpi_q ":MEAS:STAT:ITEM? DEV,RRDelay,CHANnel1,CHANnel2")

	DSO_13_CNT=$(scpi_q ":MEAS:STAT:ITEM? CNT,RRDelay,CHANnel1,CHANnel3")
	DSO_13_MIN=$(scpi_q ":MEAS:STAT:ITEM? MIN,RRDelay,CHANnel1,CHANnel3")
	DSO_13_MAX=$(scpi_q ":MEAS:STAT:ITEM? MAX,RRDelay,CHANnel1,CHANnel3")
	DSO_13_AVG=$(scpi_q ":MEAS:STAT:ITEM? AVER,RRDelay,CHANnel1,CHANnel3")
	DSO_13_DEV=$(scpi_q ":MEAS:STAT:ITEM? DEV,RRDelay,CHANnel1,CHANnel3")
}

# Check if DSO stats are valid (both channel averages must be real numbers)
dso_stats_valid() {
	scpi_val_valid "$DSO_12_AVG" && scpi_val_valid "$DSO_13_AVG"
}

# Calculate sync quality percentage from DSO average delays
# 100% = perfect sync (0ms delay), 0% = no sync
# Uses worst absolute avg across channels (max excluded - unreliable without filter caps)
# Exponential decay: quality = 100 * e^(-worst_abs_avg / 15)
dso_sync_quality() {
	local avg12_ms="$1"
	local avg13_ms="$2"
	awk "BEGIN {
		a12 = $avg12_ms; if (a12 < 0) a12 = -a12;
		a13 = $avg13_ms; if (a13 < 0) a13 = -a13;
		worst = (a12 > a13) ? a12 : a13;
		q = 100 * exp(-worst / 15);
		printf \"%.1f\", q
	}"
}

# Format DSO results for per-iteration console output
dso_format_brief() {
	if dso_stats_valid; then
		printf "| DSO: CH1-2: avg=%sms max=%sms(n=%d) CH1-3: avg=%sms max=%sms(n=%d)" \
			"$(fmt_ms "$DSO_12_AVG")" "$(fmt_ms "$DSO_12_MAX")" "$(printf '%.0f' "$DSO_12_CNT")" \
			"$(fmt_ms "$DSO_13_AVG")" "$(fmt_ms "$DSO_13_MAX")" "$(printf '%.0f' "$DSO_13_CNT")"
	else
		printf "| DSO: no valid measurements"
	fi
}

#------------------------------------------------------------------------------
# Logging functions
#------------------------------------------------------------------------------

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
	elif [ "$(awk "BEGIN {print ($FINAL_SPREAD > 0.08) ? 1 : 0}")" = "1" ]; then
		status="FAIL"
		details="(spread > 0.08%)"
	elif [ "$(awk "BEGIN {print ($FINAL_SPREAD > 0.04) ? 1 : 0}")" = "1" ]; then
		status="WARN"
		details="(spread > 0.04%)"
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
log "Wait between iterations: ${ITER_WAIT}s"
if [ -n "$DSO_IP" ]; then
	log "DSO: $DSO_IP:$DSO_PORT"
	if [ -n "$DSO_CONFIG" ]; then
		log "DSO config: $DSO_CONFIG"
	fi
fi
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

# DSO pre-flight checks (optional)
if [ -n "$DSO_IP" ]; then
	log "Checking oscilloscope connectivity..."
	DSO_DEVICE_ID=$(scpi_q "*IDN?")
	if [ -n "$DSO_DEVICE_ID" ]; then
		log "  Scope: $DSO_DEVICE_ID"
		DSO_ENABLED=1
	else
		log "Error: Cannot connect to oscilloscope at $DSO_IP:$DSO_PORT"
		exit 1
	fi

	# Apply DSO config if provided
	if [ -n "$DSO_CONFIG" ]; then
		if [ -f "$DSO_CONFIG" ]; then
			log "  Applying DSO config: $DSO_CONFIG"
			RIGOL_TOOL="$SCRIPT_DIR/tmp-debug/dso-scripts/rigol-tool.sh"
			if [ -f "$RIGOL_TOOL" ]; then
				"$RIGOL_TOOL" --command=apply-setup --input="$DSO_CONFIG" --dso-ip="$DSO_IP" >/dev/null 2>&1
				log "  DSO config applied"
			else
				log "  Warning: rigol-tool.sh not found, skipping config apply"
			fi
		else
			log "Error: DSO config file not found: $DSO_CONFIG"
			exit 1
		fi
	fi

	# Setup measurements
	log "  Setting up RRDelay measurements (CH1->CH2, CH1->CH3)..."
	dso_setup_measurements
	log "  DSO measurement enabled (wait: ${ITER_WAIT}s per iteration)"
	log "  DSO thresholds (avg-based): WARN > ${DSO_WARN_MS}ms, FAIL > ${DSO_FAIL_MS}ms"
fi

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

	# Generate random start position (2-30%)
	RANDOM_POS=$(random_position)
	log_file "Random start position: $RANDOM_POS%"

	# Step 1: Open file on master and seek to random position
	log_file "Opening file on master at $RANDOM_POS%..."

	# Stop any current playback on ALL devices (prevents stale player state)
	for device in $DEVICES; do
		kodi_rpc "$device" '{"jsonrpc":"2.0","id":"1","method":"Player.Stop","params":{"playerid":1}}' >/dev/null 2>&1 &
	done
	wait
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

	# Step 2: Run sync script with timeout (prevents hang if Kodi becomes unresponsive)
	log_file "Running sync script..."
	SYNC_OUTPUT=$(timeout 120 "$SYNC_SCRIPT" --master="$MASTER_HOST" --debuglog 2>&1)
	SYNC_EXIT=$?
	if [ $SYNC_EXIT -eq 124 ]; then
		log "WARNING: Sync script timed out (120s) on iteration $i"
		SYNC_OUTPUT="$SYNC_OUTPUT
ERROR: Sync script timed out"
	fi

	# Log full output to file
	echo "$SYNC_OUTPUT" >> "$LOG_FILE"

	# Step 3: Analyze results
	RESULT=$(analyze_sync_output "$SYNC_OUTPUT")
	STATUS=$(echo "$RESULT" | cut -d'|' -f1)
	SPREAD=$(echo "$RESULT" | cut -d'|' -f2)
	DETAILS=$(echo "$RESULT" | cut -d'|' -f3)

	# Update spread statistics (only for valid spreads)
	if [ "$SPREAD" != "999" ]; then
		TOTAL_SPREAD=$(awk "BEGIN {print $TOTAL_SPREAD + $SPREAD}")
		if [ "$(awk "BEGIN {print ($SPREAD > $MAX_SPREAD) ? 1 : 0}")" = "1" ]; then
			MAX_SPREAD="$SPREAD"
		fi
	fi

	# DSO measurement phase
	DSO_INFO=""
	if [ "$DSO_ENABLED" -eq 1 ]; then
		# Reset stats before measurement window
		dso_reset_stats

		# Wait for measurement accumulation
		log_file "DSO measurement window: ${ITER_WAIT}s..."
		sleep "$ITER_WAIT"

		# Read accumulated statistics
		dso_read_stats

		if dso_stats_valid; then
			DSO_INFO=$(dso_format_brief)
			DSO_VALID_COUNT=$((DSO_VALID_COUNT + 1))

			# Update aggregate DSO statistics
			DSO_12_AVG_MS=$(fmt_ms "$DSO_12_AVG")
			DSO_13_AVG_MS=$(fmt_ms "$DSO_13_AVG")
			DSO_12_MAX_ABS=$(abs_ms "$DSO_12_MAX")
			DSO_13_MAX_ABS=$(abs_ms "$DSO_13_MAX")

			DSO_12_TOTAL_AVG=$(awk "BEGIN {printf \"%.3f\", $DSO_12_TOTAL_AVG + $DSO_12_AVG_MS}")
			DSO_13_TOTAL_AVG=$(awk "BEGIN {printf \"%.3f\", $DSO_13_TOTAL_AVG + $DSO_13_AVG_MS}")

			# Track worst (largest absolute) max
			if [ "$(awk "BEGIN {print ($DSO_12_MAX_ABS > $DSO_12_WORST_MAX) ? 1 : 0}")" = "1" ]; then
				DSO_12_WORST_MAX="$DSO_12_MAX_ABS"
			fi
			if [ "$(awk "BEGIN {print ($DSO_13_MAX_ABS > $DSO_13_WORST_MAX) ? 1 : 0}")" = "1" ]; then
				DSO_13_WORST_MAX="$DSO_13_MAX_ABS"
			fi

			# Calculate sync quality (blends DSO + software spread)
			DSO_QUALITY=$(dso_sync_quality "$DSO_12_AVG_MS" "$DSO_13_AVG_MS")

			# Cap quality by software spread (catches large desync that DSO RRDelay misses)
			if [ "$SPREAD" != "999" ] && [ "$(awk "BEGIN {print ($SPREAD > 0) ? 1 : 0}")" = "1" ]; then
				SPREAD_MS=$(awk "BEGIN {printf \"%.1f\", $SPREAD / 100 * ${VIDEO_LENGTH} * 1000}")
				SPREAD_Q=$(awk "BEGIN {printf \"%.1f\", 100 * exp(-$SPREAD_MS / 60)}")
				if [ "$(awk "BEGIN {print ($SPREAD_Q < $DSO_QUALITY) ? 1 : 0}")" = "1" ]; then
					DSO_QUALITY="$SPREAD_Q"
				fi
			fi

			DSO_INFO="$DSO_INFO | Q:${DSO_QUALITY}%"
			DSO_TOTAL_QUALITY=$(awk "BEGIN {printf \"%.1f\", $DSO_TOTAL_QUALITY + $DSO_QUALITY}")

			# Log full DSO stats to file
			log_file "DSO CH1->CH2: cnt=$DSO_12_CNT avg=$(fmt_ms "$DSO_12_AVG")ms min=$(fmt_ms "$DSO_12_MIN")ms max=$(fmt_ms "$DSO_12_MAX")ms dev=$(fmt_ms "$DSO_12_DEV")ms"
			log_file "DSO CH1->CH3: cnt=$DSO_13_CNT avg=$(fmt_ms "$DSO_13_AVG")ms min=$(fmt_ms "$DSO_13_MIN")ms max=$(fmt_ms "$DSO_13_MAX")ms dev=$(fmt_ms "$DSO_13_DEV")ms"
			log_file "DSO sync quality: ${DSO_QUALITY}%"
		else
			DSO_INFO="| DSO: no valid measurements"
			log_file "DSO: no valid measurements this iteration"
		fi
	else
		# No DSO - just wait between iterations (unless last)
		if [ "$i" -lt "$LOOP_COUNT" ]; then
			log_file "Waiting ${ITER_WAIT}s before next iteration..."
			sleep "$ITER_WAIT"
		fi
	fi

	# DSO-based status escalation (only tighten, never loosen)
	# Uses average delay (robust against single-edge outliers from scope)
	if [ "$DSO_ENABLED" -eq 1 ] && dso_stats_valid; then
		# Check if worst average on either channel exceeds thresholds
		DSO_WORST_AVG=$(awk "BEGIN {
			a=$DSO_12_AVG_MS; b=$DSO_13_AVG_MS;
			if (a < 0) a = -a; if (b < 0) b = -b;
			printf \"%.3f\", (a > b) ? a : b
		}")

		if [ "$(awk "BEGIN {print ($DSO_WORST_AVG > $DSO_FAIL_MS) ? 1 : 0}")" = "1" ]; then
			if [ "$STATUS" != "FAIL" ]; then
				STATUS="FAIL"
				DETAILS="$DETAILS (DSO avg: ${DSO_WORST_AVG}ms > ${DSO_FAIL_MS}ms)"
			fi
		elif [ "$(awk "BEGIN {print ($DSO_WORST_AVG > $DSO_WARN_MS) ? 1 : 0}")" = "1" ]; then
			if [ "$STATUS" = "PASS" ]; then
				STATUS="WARN"
				DETAILS="$DETAILS (DSO avg: ${DSO_WORST_AVG}ms > ${DSO_WARN_MS}ms)"
			fi
		fi
	fi

	# Update statistics (after DSO may have escalated status)
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

	# Print status
	print_status "$i" "$LOOP_COUNT" "$STATUS" "$SPREAD" "$DSO_INFO (start: $RANDOM_POS%) $DETAILS"
	log_file "Result: $STATUS - spread: $SPREAD% $DETAILS"

	# Check if we should stop on failure
	if [ "$FAIL_STOP" = "yes" ] && [ "$STATUS" = "FAIL" ]; then
		log ""
		log "Stopping due to --failstop=yes"
		break
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
log "Software spread statistics:"
log "  Average: ${AVG_SPREAD}%"
log "  Maximum: ${MAX_SPREAD}%"

if [ "$DSO_ENABLED" -eq 1 ]; then
	log ""
	log "DSO Oscilloscope Measurements:"
	if [ "$DSO_VALID_COUNT" -gt 0 ]; then
		DSO_12_AVG_MEAN=$(awk "BEGIN {printf \"%.3f\", $DSO_12_TOTAL_AVG / $DSO_VALID_COUNT}")
		DSO_13_AVG_MEAN=$(awk "BEGIN {printf \"%.3f\", $DSO_13_TOTAL_AVG / $DSO_VALID_COUNT}")
		DSO_AVG_QUALITY=$(awk "BEGIN {printf \"%.1f\", $DSO_TOTAL_QUALITY / $DSO_VALID_COUNT}")
		log "  CH1->CH2 (master->slave1): avg mean=${DSO_12_AVG_MEAN}ms, worst max=${DSO_12_WORST_MAX}ms"
		log "  CH1->CH3 (master->slave2): avg mean=${DSO_13_AVG_MEAN}ms, worst max=${DSO_13_WORST_MAX}ms"
		log "  Average sync quality: ${DSO_AVG_QUALITY}%"
		log "  Valid DSO iterations: ${DSO_VALID_COUNT}/${COMPLETED}"
	else
		log "  No valid DSO measurements collected"
	fi
fi

log ""
log "Full log: $LOG_FILE"
log "=============================================="

# Exit with error if any failures
if [ "$FAIL_COUNT" -gt 0 ]; then
	exit 1
fi
exit 0
