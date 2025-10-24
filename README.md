# PrayerTime-Waybar 🕌

A Waybar module that displays Islamic prayer times and automatically plays the adhan (call to prayer). Features automatic location detection, timezone handling, and interactive mute controls with real-time status updates.

## ✨ Features

- **📍 Automatic Location Detection**: Uses IP-based geolocation to calculate prayer times (fallback: Makkah)
- **⏰ Smart Prayer Times**: Displays next prayer and countdown in Waybar tooltip
- **🔔 Auto Adhan Playback**: Plays call to prayer at correct times with multiple audio backend support
- **🔇 Interactive Mute**: Click to toggle adhan on/off with instant visual feedback
- **🎨 Customizable**: Full control over appearance and prayer calculation methods
- **🔄 Auto Refresh**: Updates prayer times daily and responds to mute changes immediately
- **🚀 Easy Install/Uninstall**: Automated scripts with backup/restore capabilities
- **⚙️ Systemd Integration**: Runs as a user service, starts automatically on login

## 📋 Requirements

### Essential
- **Waybar** (Wayland status bar)
- **Python 3.8+**
- **jq** (JSON processor for waybar scripts)
- **curl** (HTTP requests)

### Audio Backend (one of)
- **VLC** (python-vlc library + VLC player) — recommended
- **mpv**
- **ffplay** (from ffmpeg)

Install on Arch-based systems:
```bash
sudo pacman -S waybar python python-pip jq curl vlc
```

## 🚀 Installation

1. **Clone the repository:**
   ```bash
   git clone https://github.com/mehdiz5/PrayerTime-Waybar.git
   cd PrayerTime-Waybar
   ```

2. **Add your adhan audio file:**
   ```bash
   # Copy or download your preferred adhan MP3 to the project directory
   cp /path/to/your/adhan.mp3 ./azan.mp3
   
   # Or download one (example):
   # wget https://example.com/adhan.mp3 -O azan.mp3
   ```

3. **Run the installer:**
   ```bash
   ./install.sh
   ```

   The installer will:
   - Create a Python virtual environment
   - Install required Python packages
   - Prompt for your Waybar config paths (defaults provided)
   - Create backups of your Waybar config and style files
   - Add the `custom/azan` module to your Waybar config
   - Append module styles to your style.css
   - Generate and enable a systemd user service
   - Start the prayer daemon

4. **Restart Waybar** (if it doesn't auto-reload):
   ```bash
   killall waybar && waybar &
   ```

You should now see the prayer module in your Waybar!

## ⚙️ Configuration

### Prayer Calculation Method

The daemon uses [pyIslam](https://github.com/abougouffa/pyIslam) for prayer time calculations. Edit `azan_daemon.py` to change the calculation method (line ~53):

```python
def get_prayer_times():
    lat, lon, tz_name, offset = get_location_info()
    pconf = PrayerConf(lon, lat, offset, 5, 1)  # Change the 5 here
    #                                      ^
    #                                      Method ID
```

Available methods: 1 (Karachi), 2 (MWL), 3 (Egypt), 4 (Makkah), 5 (ISNA - default), 6 (France). See [pyIslam documentation](https://github.com/abougouffa/pyIslam) for details.

### Waybar Module Position

By default, the module is added to `modules-center`. To change position, edit your `~/.config/waybar/config.jsonc`:

```json
{
  "modules-left": ["..."],
  "modules-center": ["clock", "custom/azan"],  // Move here if desired
  "modules-right": ["..."]
}
```

### Styling

Customize the module appearance in `~/.config/waybar/style.css`:

```css
#custom-azan {
    color: #b4befe;              /* Icon color */
    background: transparent;
    font-size: 14px;
    padding: 0 10px;
    margin: 0 5px;
    border-radius: 8px;
}

#custom-azan:hover {
    color: #f9e2af;              /* Hover color */
    background: rgba(180, 190, 254, 0.1);
}
```

### Adhan Audio File

Replace `azan.mp3` with your preferred audio file:
```bash
cp /path/to/new-adhan.mp3 ./azan.mp3
systemctl --user restart prayer-daemon
```

## 🎮 Usage

### Interactive Controls

- **Click the module**: Toggle mute on/off (immediate visual update via signal)
- **Hover over module**: See all prayer times with next prayer highlighted

### Manual Daemon Control

```bash
# Check service status
systemctl --user status prayer-daemon

# Restart the daemon
systemctl --user restart prayer-daemon

# Stop the daemon
systemctl --user stop prayer-daemon

# View logs
journalctl --user -u prayer-daemon -f

# Check current status via API
curl http://127.0.0.1:4567/status | jq

# Toggle mute via API
curl http://127.0.0.1:4567/mute
```

## 🔍 Troubleshooting

### Module Not Appearing

1. **Verify daemon is running:**
   ```bash
   systemctl --user status prayer-daemon
   curl http://127.0.0.1:4567/status
   ```

2. **Check Waybar config was updated:**
   ```bash
   grep -A 6 '"custom/azan"' ~/.config/waybar/config.jsonc
   ```
   Should show:
   ```json
   "custom/azan": {
     "exec": "/full/path/to/scripts/waybar-azan.sh",
     "return-type": "json",
     "interval": 20,
     "on-click": "/full/path/to/scripts/waybar-azan-mute.sh",
     "signal": 20
   }
   ```

3. **Check module in modules array:**
   ```bash
   grep "modules-" ~/.config/waybar/config.jsonc | grep azan
   ```

4. **Verify scripts are executable:**
   ```bash
   ls -la scripts/waybar-azan*.sh
   ```

5. **Restart Waybar:**
   ```bash
   killall waybar && waybar &
   ```

### Daemon Fails to Start

1. **Check service logs:**
   ```bash
   journalctl --user -u prayer-daemon --no-pager -n 50
   ```

2. **Verify Python environment:**
   ```bash
   ./env/bin/python --version
   ./env/bin/pip list | grep -E "vlc|requests|pytz|islam"
   ```

3. **Test daemon manually:**
   ```bash
   ./env/bin/python azan_daemon.py
   ```

### No Adhan Sound

1. **Check audio file exists:**
   ```bash
   file azan.mp3
   mpv azan.mp3  # Test playback
   ```

2. **Verify VLC/audio player is installed:**
   ```bash
   which vlc mpv ffplay
   ```

3. **Check mute status:**
   ```bash
   curl http://127.0.0.1:4567/status | jq '.muted_status'
   ```

4. **Test VLC library:**
   ```bash
   ./env/bin/python -c "import vlc; print('VLC OK')"
   ```

### Wrong Prayer Times

1. **Check detected location:**
   ```bash
   curl https://ipinfo.io/json | jq
   ```

2. **Verify timezone:**
   ```bash
   timedatectl
   ```

3. **Check daemon location info** (look at startup logs):
   ```bash
   journalctl --user -u prayer-daemon | grep -i location
   ```

4. **Test location detection:**
   ```bash
   ./env/bin/python -c "
   import requests
   data = requests.get('https://ipinfo.io/json').json()
   print(f\"Location: {data['city']}, {data['country']}\")
   print(f\"Coordinates: {data['loc']}\")
   print(f\"Timezone: {data['timezone']}\")
   "
   ```

## 🗑️ Uninstallation

Run the automated uninstaller:

```bash
./uninstall.sh
```

The script will:
- Stop and disable the systemd service
- Kill any running daemon processes
- Remove the service file
- Restore your Waybar config and style from backups
- Optionally remove the Python virtual environment

### Verify Daemon is Stopped

After uninstalling, verify the daemon is no longer running:

```bash
# Check for running daemon process
pgrep -f azan_daemon.py

# Try to connect to API (should fail)
curl -f http://127.0.0.1:4567/status 2>/dev/null && echo "Still running!" || echo "Stopped ✓"

# Check systemd service status
systemctl --user status prayer-daemon
```

If the daemon is still running, manually stop it:

```bash
# Kill daemon process
pkill -f azan_daemon.py

# Or force kill if needed
pkill -9 -f azan_daemon.py
```

Then restart Waybar:
```bash
killall waybar && waybar &
```

To completely remove the project:
```bash
cd ..
rm -rf PrayerTime-Waybar
```

## 📁 Project Structure

```
PrayerTime-Waybar/
├── azan_daemon.py          # Main daemon (HTTP server + adhan scheduler)
├── azan.mp3                # Your adhan audio file (not included)
├── install.sh              # Automated installer
├── uninstall.sh            # Automated uninstaller
├── requirements.txt        # Python dependencies
├── scripts/
│   ├── waybar-azan.sh      # Status display script (called by Waybar)
│   └── waybar-azan-mute.sh # Mute toggle script (on-click handler)
├── waybar/
│   └── style.css           # CSS styles for the module
└── env/                    # Python virtual environment (created by installer)
```

## 🔧 API Endpoints

The daemon exposes a local HTTP API on `127.0.0.1:4567`:

### `GET /status`
Returns current prayer times and status:
```json
{
  "text": "Prayer",
  "tooltip": "<b>● Asr      : 15:23</b>\nMaghrib : 17:45\n...",
  "next_prayer": "Asr",
  "next_time": "15:23",
  "muted_status": "No"
}
```

### `GET /mute`
Toggles mute state and returns:
```json
{
  "mute": true
}
```

## 🤝 Contributing

Contributions are welcome! Areas for improvement:

- [ ] Add configuration file for easier customization
- [ ] Support more prayer calculation methods
- [ ] Add notification support (libnotify)
- [ ] Configurable adhan files per prayer
- [ ] GUI for configuration
- [ ] Systemd timer for prayer time updates
- [ ] Support for multiple locations/timezones

## 📝 License

This project is open source. Feel free to use, modify, and distribute.

## 🙏 Acknowledgments

- Uses [pyIslam](https://github.com/abougouffa/pyIslam) for prayer time calculations
- Built for [Waybar](https://github.com/Alexays/Waybar)
- Inspired by the Muslim community's need for prayer time tools on Linux
- Custom adhan for specific prayers
- Prayer reminder notifications
- Multiple audio file support
- Prayer time adjustments

## 📝 License

This project is open source under the MIT License.