#!/system/bin/sh
LOG=/data/local/tmp/wsa-bt-bridge.log
STATE=/data/local/tmp/wsa-bt-health.json
MODULE=/data/adb/modules/wsa_bt_bridge

sleep 8

AF="false"
AP="false"
DAEMON="false"

dumpsys media.audio_flinger >/dev/null 2>&1 && AF="true"
dumpsys media.audio_policy >/dev/null 2>&1 && AP="true"
pidof wsa-btd >/dev/null 2>&1 && DAEMON="true"

if [ "$AF" != "true" ] || [ "$AP" != "true" ]; then
  echo "[health] Audio service failure detected; disabling module overlay for next boot" >> "$LOG"
  touch "$MODULE/disable"
  echo "{"audio_flinger":$AF,"audio_policy":$AP,"daemon":$DAEMON,"healthy":false,"rollback_scheduled":true}" > "$STATE"
  exit 1
fi

echo "{"audio_flinger":$AF,"audio_policy":$AP,"daemon":$DAEMON,"healthy":true,"rollback_scheduled":false}" > "$STATE"
exit 0
