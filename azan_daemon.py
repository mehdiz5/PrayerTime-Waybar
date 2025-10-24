#!/usr/bin/env python3
import json
import threading
import time
from datetime import datetime, date
from http.server import BaseHTTPRequestHandler, HTTPServer

import requests
import pytz
import vlc  # for stoppable playback
from pyIslam.praytimes import PrayerConf, Prayer
import subprocess
import shutil

# ==============================================
# CONFIGURATION
# ==============================================
ADHAN_FILE = "azan.mp3"  # Replace with your audio file path
CHECK_INTERVAL = 60  # seconds
PORT = 4567
MUTE = False
PLAYER = None  # VLC player instance (VLC player or subprocess.Popen)

# Try to initialize libVLC. If it fails (e.g. python-vlc can't find libvlc),
# fall back to using a subprocess-based player (cvlc/mpv/ffplay) below.
try:
    VLC_INSTANCE = vlc.Instance('--no-xlib')  # Create VLC instance without X11 dependency
    VLC_AVAILABLE = True
except Exception as e:
    print("WARNING: VLC instance creation failed:", e)
    VLC_INSTANCE = None
    VLC_AVAILABLE = False

# ==============================================
# LOCATION & PRAYER TIME SETUP
# ==============================================
def get_location_info():
    try:
        data = requests.get("https://ipinfo.io/json", timeout=5).json()
        lat, lon = map(float, data["loc"].split(","))
        tz_name = data["timezone"]
        tz = pytz.timezone(tz_name)
        offset = datetime.now(tz).utcoffset().total_seconds() / 3600
        return lat, lon, tz_name, offset
    except Exception as e:
        print("WARNING: Could not fetch location info:", e)
        return 21.4225, 39.8262, "Asia/Riyadh", 3  # fallback (Makkah)

def get_prayer_times():
    lat, lon, tz_name, offset = get_location_info()
    pconf = PrayerConf(lon, lat, offset, 5, 1)
    pt = Prayer(pconf, date.today())
    return {
        "Fajr": pt.fajr_time().strftime("%H:%M"),
        "Dhuhr": pt.dohr_time().strftime("%H:%M"),
        "Asr": pt.asr_time().strftime("%H:%M"),
        "Maghrib": pt.maghreb_time().strftime("%H:%M"),
        "Isha": pt.ishaa_time().strftime("%H:%M"),
    }, tz_name

PRAYER_TIMES, TZ_NAME = get_prayer_times()
MAX_LEN = max(len(k) for k in PRAYER_TIMES.keys())

# ==============================================
# ADHAN CONTROL
# ==============================================
def play_adhan():
    global PLAYER
    stop_adhan()
    # Prefer python-vlc if available
    if VLC_AVAILABLE and VLC_INSTANCE is not None:
        try:
            PLAYER = VLC_INSTANCE.media_player_new()
            media = VLC_INSTANCE.media_new(ADHAN_FILE)
            PLAYER.set_media(media)
            PLAYER.play()
            print("RUNNING: Playing adhan via libVLC...")
            return
        except Exception as e:
            print("WARNING: python-vlc playback failed:", e)

    # Fallback: try system players via subprocess (cvlc, mpv, ffplay)
    for cmd in ("cvlc", "vlc", "mpv", "ffplay", "play"):
        path = shutil.which(cmd)
        if path:
            try:
                if cmd == "ffplay":
                    # ffplay needs -nodisp -autoexit
                    PLAYER = subprocess.Popen([path, "-nodisp", "-autoexit", ADHAN_FILE], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                elif cmd == "play":
                    PLAYER = subprocess.Popen([path, ADHAN_FILE], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                else:
                    # cvlc/vlc/mpv support --play-and-exit or --no-video
                    args = [path]
                    if cmd in ("cvlc", "vlc"):
                        args += ["--intf", "dummy", "--play-and-exit", ADHAN_FILE]
                    else:  # mpv
                        args += ["--no-terminal", "--really-quiet", ADHAN_FILE]
                    PLAYER = subprocess.Popen(args, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

                print(f"RUNNING: Playing adhan via {cmd}...")
                return
            except Exception as e:
                print(f"WARNING: Failed to play with {cmd}:", e)

    print("ERROR: No playback method available (libVLC missing and no system player found).")

def stop_adhan():
    global PLAYER
    if not PLAYER:
        return

    # If we're using python-vlc player
    try:
        if hasattr(PLAYER, "is_playing") and PLAYER.is_playing():
            print("STOPPING: Stopping adhan (libVLC)...")
            PLAYER.stop()
    except Exception:
        pass

    # If we started a subprocess, terminate it
    try:
        if isinstance(PLAYER, subprocess.Popen):
            print("STOPPING: Terminating subprocess player...")
            PLAYER.terminate()
            try:
                PLAYER.wait(timeout=2)
            except Exception:
                PLAYER.kill()
    except Exception:
        pass

    PLAYER = None

# ==============================================
# ADHAN SCHEDULER
# ==============================================
def adhan_loop():
    global PRAYER_TIMES, TZ_NAME, MUTE
    played_today = set()
    current_day = date.today()

    while True:
        now_dt = datetime.now(pytz.timezone(TZ_NAME))
        # Use the actual current time (HH:MM)
        now_str = now_dt.strftime("%H:%M")
        # now_str = PRAYER_TIMES["Isha"]  # Test adhan by matching Isha time --- IGNORE ---

        if now_dt.date() != current_day:
            PRAYER_TIMES, TZ_NAME = get_prayer_times()
            played_today.clear()
            current_day = now_dt.date()
            print("Updated prayer times for new day")

        for name, time_str in PRAYER_TIMES.items():
            if now_str == time_str and name not in played_today:
                if not MUTE:
                    print(f"{name} time! Playing adhan.")
                    play_adhan()
                else:
                    print(f"{name} time (muted)")
                played_today.add(name)

        time.sleep(CHECK_INTERVAL)

# ==============================================
# HTTP SERVER (for Waybar)
# ==============================================
class AzanRequestHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        global MUTE
        if self.path == "/status":
            now = datetime.now(pytz.timezone(TZ_NAME)).strftime("%H:%M")
            next_prayer = None
            tooltip_lines = []

            for name, time_str in PRAYER_TIMES.items():
                padded = name.ljust(MAX_LEN)
                if not next_prayer and time_str > now:
                    tooltip_lines.append(f"<b>● {padded}: {time_str}</b>")
                    next_prayer = name
                else:
                    tooltip_lines.append(f"{padded}: {time_str}")

            if not next_prayer:
                first_name = list(PRAYER_TIMES.keys())[0]
                tooltip_lines[0] = f"<b>● {first_name.ljust(MAX_LEN)}: {PRAYER_TIMES[first_name]}</b>"
                next_prayer = first_name

            tooltip_html = "\\n".join(tooltip_lines)
            data = {
                "text": "Prayer",  # keep icon text static
                "tooltip": tooltip_html,
                "next_prayer": next_prayer,
                "next_time": PRAYER_TIMES[next_prayer],
                "muted_status": "Yes" if MUTE else "No"
            }
            self.respond(data)

        elif self.path == "/mute":
            MUTE = not MUTE
            if MUTE:
                stop_adhan()  # immediately stop if playing
            state = "muted" if MUTE else "unmuted"
            print(f"RUNNING: Mute toggled → {state}")
            self.respond({"mute": MUTE})

        else:
            self.send_response(404)
            self.end_headers()

    def respond(self, data):
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(json.dumps(data).encode())

def run_server():
    server = HTTPServer(("127.0.0.1", PORT), AzanRequestHandler)
    print(f"Azan daemon running on 127.0.0.1:{PORT}")
    server.serve_forever()

# ==============================================
# MAIN
# ==============================================
if __name__ == "__main__":
    print("Starting Azan Daemon...")
    threading.Thread(target=adhan_loop, daemon=True).start()
    run_server()
