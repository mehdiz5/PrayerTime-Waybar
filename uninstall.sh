#!/bin/bash
set -e

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "PrayerTime-Waybar uninstaller"

# Prompt for waybar config paths
read -p "Enter path to waybar config file (default: ~/.config/waybar/config.jsonc): " WAYBAR_CONFIG
WAYBAR_CONFIG=${WAYBAR_CONFIG:-~/.config/waybar/config.jsonc}
WAYBAR_CONFIG=$(eval echo "$WAYBAR_CONFIG")

read -p "Enter path to waybar style.css file (default: ~/.config/waybar/style.css): " WAYBAR_STYLE
WAYBAR_STYLE=${WAYBAR_STYLE:-~/.config/waybar/style.css}
WAYBAR_STYLE=$(eval echo "$WAYBAR_STYLE")

echo "Stopping and disabling systemd user service..."
systemctl --user stop prayer-daemon 2>/dev/null || true
systemctl --user disable prayer-daemon 2>/dev/null || true

SERVICE_PATH="$HOME/.config/systemd/user/prayer-daemon.service"
if [ -f "$SERVICE_PATH" ]; then
  rm -f "$SERVICE_PATH"
  systemctl --user daemon-reload || true
  echo "Removed service file at $SERVICE_PATH"
fi

# Ensure daemon process is killed
echo "Ensuring daemon process is stopped..."
pkill -f azan_daemon.py 2>/dev/null || true
sleep 1

# Double-check and force kill if still running
if pgrep -f azan_daemon.py > /dev/null; then
  echo "Force killing remaining daemon processes..."
  pkill -9 -f azan_daemon.py 2>/dev/null || true
fi

# Restore Waybar config and style from backups if available
RESTORED_CFG=false
RESTORED_CSS=false

if [ -f "$WAYBAR_CONFIG.backup" ]; then
  cp "$WAYBAR_CONFIG.backup" "$WAYBAR_CONFIG"
  RESTORED_CFG=true
  echo "Restored Waybar config from backup"
fi

if [ -f "$WAYBAR_STYLE.backup" ]; then
  cp "$WAYBAR_STYLE.backup" "$WAYBAR_STYLE"
  RESTORED_CSS=true
  echo "Restored Waybar style from backup"
fi

# If no backups, attempt surgical removal of module from config
if [ "$RESTORED_CFG" != true ] && [ -f "$WAYBAR_CONFIG" ]; then
  echo "No Waybar config backup found; attempting to remove module entries..."
  PY_HELPER=$(mktemp)
  cat >"$PY_HELPER" <<'PY'
import json, re, os, sys

cfg_path = os.environ['WAYBAR_CONFIG']

def read_text(p):
    with open(p, 'r', encoding='utf-8') as f:
        return f.read()

def strip_jsonc(s):
    s = re.sub(r"/\*.*?\*/", "", s, flags=re.S)
    s = re.sub(r"(^|\s)//.*$", "", s, flags=re.M)
    s = re.sub(r",\s*(\}|\])", r"\1", s)
    return s

raw = read_text(cfg_path)
try:
    data = json.loads(raw)
except Exception:
    data = json.loads(strip_jsonc(raw))

for k in ("modules-right", "modules-center", "modules-left"):
    if isinstance(data.get(k), list) and "custom/azan" in data[k]:
        data[k] = [m for m in data[k] if m != "custom/azan"]

if "custom/azan" in data:
    del data["custom/azan"]

with open(cfg_path, 'w', encoding='utf-8') as f:
    f.write(json.dumps(data, indent=2, ensure_ascii=False) + "\n")
print("Removed custom/azan from Waybar config if present")
PY
  WAYBAR_CONFIG="$WAYBAR_CONFIG" python3 "$PY_HELPER" || true
  rm -f "$PY_HELPER"
fi

# If no CSS backup, we cannot safely remove appended styles without markers
if [ "$RESTORED_CSS" != true ]; then
  echo "No Waybar style backup found; leaving styles as-is. You may manually edit $WAYBAR_STYLE if needed."
fi

# Optionally remove the virtual environment
read -p "Remove project virtual environment at $SCRIPT_DIR/env? [y/N]: " RM_ENV
RM_ENV=${RM_ENV:-N}
if [[ "$RM_ENV" =~ ^[Yy]$ ]]; then
  rm -rf "$SCRIPT_DIR/env"
  echo "Removed virtual environment."
fi

echo "Uninstall complete."
echo "Refreshing Waybar..."
pkill -SIGUSR2 waybar 2>/dev/null || echo "Note: Waybar not running or couldn't be refreshed."
