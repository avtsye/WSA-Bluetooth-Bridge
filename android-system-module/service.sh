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

while true; do
  echo "Starting wsa-btd ($ABI)"
  "$BIN"
  code=$?
  echo "wsa-btd exited with $code; restarting in 3 seconds"
  sleep 3
done
