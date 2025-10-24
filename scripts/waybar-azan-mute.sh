#!/bin/bash
set -e

# Toggle mute state on the daemon; output is ignored by Waybar
curl -fsS 127.0.0.1:4567/mute >/dev/null || true

# Trigger an immediate refresh; module must have "signal": 20 in Waybar config
pkill -SIGRTMIN+20 waybar 2>/dev/null || true