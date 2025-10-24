#!/bin/bash
set -e

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Ensure python3 and pip are available
if ! command -v python3 &> /dev/null; then
    echo "Error: python3 is required but not installed"
    exit 1
fi

# Create virtual environment if it doesn't exist
if [ ! -d "env" ]; then
    echo "Creating virtual environment..."
    python3 -m venv env
fi



# Activate virtual environment and install dependencies
echo "Installing Python dependencies..."
source env/bin/activate
pip install -r requirements.txt

# Prompt for waybar config paths
read -p "Enter path to waybar config file (default: ~/.config/waybar/config.jsonc): " WAYBAR_CONFIG
WAYBAR_CONFIG=${WAYBAR_CONFIG:-~/.config/waybar/config.jsonc}
WAYBAR_CONFIG=$(eval echo "$WAYBAR_CONFIG")  # Expand ~ to home directory

read -p "Enter path to waybar style.css file (default: ~/.config/waybar/style.css): " WAYBAR_STYLE
WAYBAR_STYLE=${WAYBAR_STYLE:-~/.config/waybar/style.css}
WAYBAR_STYLE=$(eval echo "$WAYBAR_STYLE")  # Expand ~ to home directory

# Verify files exist
if [ ! -f "$WAYBAR_CONFIG" ]; then
    echo "Error: Waybar config file not found at $WAYBAR_CONFIG"
    exit 1
fi
if [ ! -f "$WAYBAR_STYLE" ]; then
    echo "Error: Waybar style file not found at $WAYBAR_STYLE"
    exit 1
fi

# Create backups
cp "$WAYBAR_CONFIG" "$WAYBAR_CONFIG.backup"
cp "$WAYBAR_STYLE" "$WAYBAR_STYLE.backup"
echo "Created backups of waybar config files"


# Ensure required CLI tools
if ! command -v curl >/dev/null 2>&1; then
  echo "Warning: curl is not installed; waybar module may not fetch status."
fi
if ! command -v jq >/dev/null 2>&1; then
  echo "Warning: jq is not installed; waybar module output parsing will fail. Please install jq."
fi

# Add or update module configuration robustly
echo "Adding prayer module configuration..."

PY_HELPER=$(mktemp)
cat >"$PY_HELPER" <<'PY'
import json, re, sys, os

cfg_path = os.environ['WAYBAR_CONFIG']
backup_path = cfg_path + '.backup'
project_dir = os.environ['PROJECT_DIR']

def read_text(path):
    with open(path, 'r', encoding='utf-8') as f:
        return f.read()

def strip_jsonc(s: str) -> str:
    # Remove /* ... */ comments
    s = re.sub(r"/\*.*?\*/", "", s, flags=re.S)
    # Remove // comments (naive: ignore those inside quotes most of the time)
    s = re.sub(r"(^|\s)//.*$", "", s, flags=re.M)
    # Remove trailing commas before } or ]
    s = re.sub(r",\s*(\}|\])", r"\1", s)
    return s

def try_parse(text: str):
    try:
        return json.loads(text)
    except Exception:
        text2 = strip_jsonc(text)
        return json.loads(text2)

def ensure_list(d, key):
    if key not in d or not isinstance(d[key], list):
        d[key] = []
    return d[key]

raw = read_text(cfg_path)
try:
    data = try_parse(raw)
except Exception:
    # Try backup
    data = try_parse(read_text(backup_path))

# Determine modules array to use (prefer center, then right, then left)
target_key = None
for k in ("modules-center", "modules-right", "modules-left"):
    if k in data and isinstance(data[k], list):
        target_key = k
        break
if target_key is None:
    target_key = "modules-center"
    data[target_key] = []

modules = data[target_key]
if "custom/azan" not in modules:
    modules.append("custom/azan")

# Define module object
module_obj = {
    "exec": os.path.join(project_dir, "scripts/waybar-azan.sh"),
    "return-type": "json",
    "interval": 20,
    "on-click": os.path.join(project_dir, "scripts/waybar-azan-mute.sh"),
    "signal": 20
}

data["custom/azan"] = module_obj

# Write back (pretty JSON; comments will be removed)
out = json.dumps(data, indent=2, ensure_ascii=False)
with open(cfg_path, 'w', encoding='utf-8') as f:
    f.write(out + "\n")

print(f"Updated {cfg_path} with custom/azan in {target_key}")
PY

PROJECT_DIR="$SCRIPT_DIR" WAYBAR_CONFIG="$WAYBAR_CONFIG" python3 "$PY_HELPER"
rm -f "$PY_HELPER"

# Copy CSS styles
cat "$SCRIPT_DIR/waybar/style.css" >> "$WAYBAR_STYLE"
echo "Added prayer module styles to waybar style.css"

# Ensure scripts are executable
chmod +x "$SCRIPT_DIR/scripts/waybar-azan.sh" "$SCRIPT_DIR/scripts/waybar-azan-mute.sh"

# Create systemd user service with correct paths
mkdir -p ~/.config/systemd/user/
SERVICE_PATH=~/.config/systemd/user/prayer-daemon.service
cat > "$SERVICE_PATH" <<EOT
[Unit]
Description=Prayer Times Daemon for Waybar
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=$SCRIPT_DIR
ExecStart=$SCRIPT_DIR/env/bin/python $SCRIPT_DIR/azan_daemon.py
Restart=on-failure
RestartSec=5
Environment=PYTHONUNBUFFERED=1

[Install]
WantedBy=default.target
EOT

# Enable and start the service
echo "Enabling and starting prayer-daemon service..."
systemctl --user daemon-reload
systemctl --user enable prayer-daemon
systemctl --user restart prayer-daemon || systemctl --user start prayer-daemon

echo "Installation complete!"
echo "Refreshing Waybar..."
pkill -SIGUSR2 waybar 2>/dev/null || echo "Note: Waybar not running or couldn't be refreshed. Start Waybar to see the module."
