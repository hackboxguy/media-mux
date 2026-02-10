#!/usr/bin/env python3
"""
NTP-Synchronized Playback Trigger Service for Media-Mux.

Listens on UDP port 9199 for trigger messages containing a future
NTP timestamp and a Kodi JSON-RPC command. Busy-waits until the
specified timestamp, then sends the command to localhost Kodi.

This eliminates network jitter from synchronized playback resume
by having all devices execute the command at the same wall-clock
moment, using chrony NTP for sub-millisecond time agreement.

Protocol v1 messages (JSON over UDP):

  Trigger (relative delay - preferred, works from any machine):
    {"v":1, "type":"trigger", "delay":<seconds_float>, "rpc":<json_rpc_payload>}

  Trigger (absolute timestamp - requires caller clock to be NTP-synced with receivers):
    {"v":1, "type":"trigger", "t":<epoch_float>, "rpc":<json_rpc_payload>}

  Ping:    {"v":1, "type":"ping"}
  Pong:    {"v":1, "type":"pong", "time":<epoch_float>}
"""

import socket
import json
import time
import syslog
import http.client
import signal
import sys

# Configuration
UDP_PORT = 9199
KODI_HOST = "127.0.0.1"
KODI_PORT = 8888
ALLOWED_SUBNET = "192.168.8."
MAX_MESSAGE_SIZE = 2048
SPIN_THRESHOLD = 0.005        # 5ms: switch from sleep to busy-spin
MAX_FUTURE_SECONDS = 10.0     # reject triggers more than 10s in the future
MAX_PAST_SECONDS = 5.0        # reject triggers more than 5s in the past
PROTOCOL_VERSION = 1


def log_info(msg):
    syslog.syslog(syslog.LOG_INFO, msg)


def log_warn(msg):
    syslog.syslog(syslog.LOG_WARNING, msg)


def wait_until(target_wall_time):
    """
    Wait until the wall clock reaches target_wall_time.
    Uses monotonic clock for the actual spin to avoid NTP step issues.
    Returns True if waited successfully, False if timestamp was stale.
    """
    delta = target_wall_time - time.time()

    if delta < -MAX_PAST_SECONDS:
        return False  # too old, discard

    if delta <= 0:
        return True  # slightly late, execute immediately

    if delta > MAX_FUTURE_SECONDS:
        return False  # too far in future, reject

    # Convert to monotonic deadline
    mono_deadline = time.monotonic() + delta

    # Phase 1: sleep (zero CPU) until ~5ms before deadline
    sleep_duration = delta - SPIN_THRESHOLD
    if sleep_duration > 0:
        time.sleep(sleep_duration)

    # Phase 2: busy-spin the final stretch for sub-ms precision
    while time.monotonic() < mono_deadline:
        pass

    return True


def send_kodi_rpc(payload_dict):
    """
    Send JSON-RPC command to local Kodi via HTTP POST.
    Uses http.client (stdlib) to avoid external dependencies.
    """
    try:
        body = json.dumps(payload_dict)
        conn = http.client.HTTPConnection(KODI_HOST, KODI_PORT, timeout=3)
        conn.request("POST", "/jsonrpc", body,
                      {"Content-Type": "application/json"})
        resp = conn.getresponse()
        conn.close()
        return resp.status == 200
    except Exception as e:
        log_warn(f"Kodi RPC failed: {e}")
        return False


def handle_trigger(msg, sender_addr):
    """Handle a trigger message: wait until timestamp, then execute RPC."""
    rpc_payload = msg["rpc"]

    # Support both relative delay and absolute timestamp
    if "delay" in msg:
        # Relative mode: compute target from local clock + delay
        delay = msg["delay"]
        if delay < 0 or delay > MAX_FUTURE_SECONDS:
            log_warn(f"Trigger delay {delay:.3f}s out of range from {sender_addr[0]}")
            return
        target_time = time.time() + delay
        delta_ms = delay * 1000
    elif "t" in msg:
        # Absolute mode: use provided timestamp directly
        target_time = msg["t"]
        delta_ms = (target_time - time.time()) * 1000
    else:
        log_warn(f"Trigger missing 't' or 'delay' from {sender_addr[0]}")
        return

    log_info(f"Trigger from {sender_addr[0]}: execute in {delta_ms:.1f}ms")

    # Pre-build request body and pre-connect to Kodi DURING the wait phase.
    # This eliminates ~2-5ms of TCP setup + JSON serialization AFTER the spin,
    # so the HTTP POST fires with minimal latency once the target time arrives.
    body = json.dumps(rpc_payload)
    try:
        conn = http.client.HTTPConnection(KODI_HOST, KODI_PORT, timeout=3)
        conn.connect()
    except Exception as e:
        log_warn(f"Kodi pre-connect failed: {e}")
        return

    if not wait_until(target_time):
        conn.close()
        if delta_ms < -MAX_PAST_SECONDS * 1000:
            log_warn(f"Trigger {-delta_ms:.0f}ms in past, discarding")
        else:
            log_warn(f"Trigger {delta_ms:.0f}ms in future, rejecting")
        return

    # Execute - TCP already connected, body already serialized
    try:
        conn.request("POST", "/jsonrpc", body,
                      {"Content-Type": "application/json"})
        actual_delta_ms = (time.time() - target_time) * 1000
        resp = conn.getresponse()
        conn.close()
        ok = resp.status == 200
    except Exception as e:
        actual_delta_ms = (time.time() - target_time) * 1000
        log_warn(f"Kodi RPC failed: {e}")
        ok = False
    log_info(f"Executed: success={ok}, accuracy={actual_delta_ms:+.2f}ms")


def handle_ping(sender_addr, sock):
    """Respond to ping with pong + current time."""
    pong = json.dumps({
        "v": PROTOCOL_VERSION,
        "type": "pong",
        "time": time.time()
    }).encode()
    sock.sendto(pong, sender_addr)


def main():
    syslog.openlog("ntp-trigger", syslog.LOG_PID, syslog.LOG_DAEMON)
    log_info(f"Starting on UDP port {UDP_PORT}")

    # Graceful shutdown
    running = True

    def shutdown(signum, frame):
        nonlocal running
        running = False

    signal.signal(signal.SIGTERM, shutdown)
    signal.signal(signal.SIGINT, shutdown)

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.bind(("0.0.0.0", UDP_PORT))
    sock.settimeout(1.0)  # allow periodic check for shutdown signal

    log_info("Listening for trigger messages")

    while running:
        try:
            data, addr = sock.recvfrom(MAX_MESSAGE_SIZE)
        except socket.timeout:
            continue
        except OSError:
            break

        sender_ip = addr[0]

        # Subnet check
        if not sender_ip.startswith(ALLOWED_SUBNET) and sender_ip != "127.0.0.1":
            log_warn(f"Rejected packet from {sender_ip}")
            continue

        # Parse message
        try:
            msg = json.loads(data.decode("utf-8"))
        except (json.JSONDecodeError, UnicodeDecodeError) as e:
            log_warn(f"Malformed message from {sender_ip}: {e}")
            continue

        # Version check
        if msg.get("v", 0) != PROTOCOL_VERSION:
            log_warn(f"Unknown protocol version {msg.get('v')} from {sender_ip}")
            continue

        # Dispatch by type
        msg_type = msg.get("type")
        if msg_type == "trigger":
            if "rpc" not in msg:
                log_warn(f"Trigger missing 'rpc' from {sender_ip}")
                continue
            if "t" not in msg and "delay" not in msg:
                log_warn(f"Trigger missing 't' or 'delay' from {sender_ip}")
                continue
            handle_trigger(msg, addr)
        elif msg_type == "ping":
            handle_ping(addr, sock)
        else:
            log_warn(f"Unknown message type '{msg_type}' from {sender_ip}")

    sock.close()
    log_info("Stopped")
    syslog.closelog()


if __name__ == "__main__":
    main()
