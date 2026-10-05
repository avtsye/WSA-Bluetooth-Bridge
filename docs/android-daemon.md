# Android bridge daemon

`wsa-btd` is the long-lived Android/WSA-side bridge boundary.

It deliberately does **not** pretend to be the Android Bluetooth framework yet. Instead it provides a stable internal IPC endpoint that a future Bluetooth HAL/framework adapter can use.

## Current behavior

- Opens Android abstract Unix socket `@wsa_bt_bridge`.
- Waits for an internal client.
- Connects to the Windows bridge host at `127.0.0.1:17890`.
- Transparently forwards protocol-v1 JSONL messages in both directions.

During the current PoC, `adb reverse tcp:17890 tcp:17890` still supplies the host transport.

## Why this exists

The final Android stack should look like:

```
Bluetooth framework / HAL adapter
        |
        | local IPC
        v
     wsa-btd
        |
        | host transport
        v
WsaBluetoothHost.exe
```

That keeps Windows transport details out of the framework integration layer.

## Manual test

After building the ARM64 or x86_64 binary appropriate for WSA:

```sh
adb push wsa-btd /data/local/tmp/wsa-btd
adb shell chmod 755 /data/local/tmp/wsa-btd
adb shell /data/local/tmp/wsa-btd
```

The expected log is:

```text
wsa-btd: ready on abstract socket @wsa_bt_bridge
```

A later milestone will install and start this as a privileged boot service.
