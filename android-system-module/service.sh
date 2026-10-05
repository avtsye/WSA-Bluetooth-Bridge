#!/system/bin/sh
MODDIR=${0%/*}
LOG=/data/local/tmp/wsa-bt-bridge.log

exec >>"$LOG" 2>&1
echo "=== WSA Bluetooth Bridge boot $(date) ==="

ABI="$(getprop ro.product.cpu.abi)"
case "$ABI" in
  x86_64*)
    BIN="$MODDIR/bin/x86_64/wsa-btd"
    ;;
  arm64-v8a*)
    BIN="$MODDIR/bin/arm64-v8a/wsa-btd"
    ;;
  *)
    echo "Unsupported ABI: $ABI"
    exit 1
    ;;
esac

chmod 0755 "$BIN"
pkill -f '/wsa-btd' 2>/dev/null || true

i=0
while [ "$i" -lt 60 ]; do
  [ "$(getprop sys.boot_completed)" = "1" ] && break
  sleep 2
  i=$((i + 1))
done

PROBE="$MODDIR/audio-env.sh"
chmod 0755 "$PROBE" 2>/dev/null || true

# Capture the exact WSA Audio HAL/AudioPolicy environment after Android boot.
"$PROBE" || echo "audio environment probe failed"

while true; do
  echo "Starting wsa-btd ($ABI)"
  "$BIN" &
  pid=$!
  sleep 2
  "$PROBE" || true
  wait "$pid"
  code=$?
  echo "wsa-btd exited with $code; restarting in 3 seconds"
  sleep 3
done
