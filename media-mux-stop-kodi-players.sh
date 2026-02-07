#!/bin/sh
#
# media-mux-stop-kodi-players.sh
# Stops playback on all media-mux Kodi players on the network
#
# Usage: media-mux-stop-kodi-players.sh [OPTIONS]
#   --debuglog           Enable verbose debug output
#   --help               Show this help message

#------------------------------------------------------------------------------
# Default configuration
#------------------------------------------------------------------------------
KODI_PORT="8888"
CURL_TIMEOUT=5
MAX_RETRIES=3
DEBUG_LOG=0

#------------------------------------------------------------------------------
# Parse command line arguments
#------------------------------------------------------------------------------
show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Stop playback on all media-mux Kodi players on the network."
    echo ""
    echo "Options:"
    echo "  --debuglog           Enable verbose debug output"
    echo "  --help               Show this help message"
    exit 0
}

for arg in "$@"; do
    case $arg in
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
log() {
    logger -t "media-mux-stop" "$1"
}

debug() {
    if [ $DEBUG_LOG -eq 1 ]; then
        echo "[DEBUG] $1"
    fi
}

#------------------------------------------------------------------------------
# Send JSON-RPC command to stop player
#------------------------------------------------------------------------------
stop_player() {
    local host="$1"
    local attempt=1
    local resp=""

    while [ $attempt -le $MAX_RETRIES ]; do
        # First, get active players
        resp=$(curl -s --connect-timeout $CURL_TIMEOUT -m $((CURL_TIMEOUT * 2)) \
            -X POST -H "content-type:application/json" \
            "http://${host}:${KODI_PORT}/jsonrpc" \
            -d '{"jsonrpc":"2.0","method":"Player.GetActivePlayers","id":1}' 2>/dev/null)

        if echo "$resp" | grep -q '"result"'; then
            # Check if there's an active player
            player_id=$(echo "$resp" | jq -r '.result[0].playerid // empty' 2>/dev/null)

            if [ -n "$player_id" ]; then
                debug "Found active player $player_id on $host, stopping..."

                # Stop the player
                stop_resp=$(curl -s --connect-timeout $CURL_TIMEOUT -m $((CURL_TIMEOUT * 2)) \
                    -X POST -H "content-type:application/json" \
                    "http://${host}:${KODI_PORT}/jsonrpc" \
                    -d "{\"jsonrpc\":\"2.0\",\"method\":\"Player.Stop\",\"params\":{\"playerid\":$player_id},\"id\":1}" 2>/dev/null)

                if echo "$stop_resp" | grep -q '"result"'; then
                    debug "Successfully stopped player on $host"
                    return 0
                fi
            else
                debug "No active player on $host"
                return 0
            fi
        fi

        attempt=$((attempt + 1))
        [ $attempt -le $MAX_RETRIES ] && sleep 0.3
    done

    debug "Failed to stop player on $host after $MAX_RETRIES attempts"
    return 1
}

#------------------------------------------------------------------------------
# Discover all media-mux devices on the network
#------------------------------------------------------------------------------
discover_devices() {
    avahi-browse -art 2>/dev/null | \
        grep -A2 "IPv4 media-mux" | \
        grep "address = " | \
        sed 's/.*address = \[\(.*\)\]/\1/' | \
        grep -v "127.0.0.1" | \
        sort -u
}

#------------------------------------------------------------------------------
# Main
#------------------------------------------------------------------------------
log "Starting stop on all media-mux devices"
debug "Discovering devices via avahi-browse..."

DEVICES=$(discover_devices)

if [ -z "$DEVICES" ]; then
    log "No media-mux devices found"
    echo "No media-mux devices found on network"
    exit 1
fi

DEVICE_COUNT=$(echo "$DEVICES" | wc -l)
log "Found $DEVICE_COUNT device(s)"
debug "Devices: $(echo $DEVICES | tr '\n' ' ')"

# Stop playback on all devices
STOPPED=0
FAILED=0

for device in $DEVICES; do
    debug "Stopping playback on $device..."
    if stop_player "$device"; then
        STOPPED=$((STOPPED + 1))
        log "Stopped: $device"
    else
        FAILED=$((FAILED + 1))
        log "Failed to stop: $device"
    fi
done

log "Stop complete: $STOPPED stopped, $FAILED failed out of $DEVICE_COUNT devices"
echo "Stopped $STOPPED/$DEVICE_COUNT players"

if [ $FAILED -gt 0 ]; then
    exit 1
fi
exit 0
