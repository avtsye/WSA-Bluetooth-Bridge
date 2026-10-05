#!/system/bin/sh
MARKER=/data/local/tmp/wsa-bt-enable-policy
STATE=/data/local/tmp/wsa-bt-policy-state.json

touch "$MARKER"
chmod 0600 "$MARKER"
echo '{"activation_requested":true,"restart_required":true}' > "$STATE"
echo "WSA Bluetooth audio policy activation requested. Restart Android/WSA to apply."
