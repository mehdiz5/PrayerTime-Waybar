#!/bin/bash
DATA=$(curl -s http://127.0.0.1:4567/status)

ICON="Prayer" # mosque icon

NEXT=$(echo "$DATA" | jq -r '.next_prayer')
TIME=$(echo "$DATA" | jq -r '.next_time')
TOOLTIP=$(echo "$DATA" | jq -r '.tooltip')
MUTE=$(echo "$DATA" | jq -r '.muted_status')
echo "{\"text\": \"$ICON\", \"tooltip\": \"$TOOLTIP \\n\\nMUTE = $MUTE\"}"