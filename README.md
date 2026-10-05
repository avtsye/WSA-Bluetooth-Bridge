# WSA Bluetooth Bridge

Experimental Bluetooth/BLE support layer for Windows Subsystem for Android (WSA).

## Goal

Make ordinary Android Bluetooth APIs inside WSA usable by routing Bluetooth operations to the Windows host, while keeping the Android-side integration below application level.

The long-term target is:

```
Android app
  -> Android Bluetooth framework
  -> WSA Bluetooth backend / HAL
  -> bridge transport
  -> Windows Bluetooth stack
  -> physical adapter
```

The first proof of concept deliberately implements **BLE scanning only**.

## Current milestone: BLE scan transport

The initial host program:

- Uses `Windows.Devices.Bluetooth.Advertisement.BluetoothLEAdvertisementWatcher`.
- Accepts a small newline-delimited JSON protocol over TCP.
- Streams BLE advertisements to the WSA side.
- Does not pair, connect, write, or change Bluetooth devices.

During development, `adb reverse` is used only as a temporary transport:

```powershell
adb reverse tcp:17890 tcp:17890
```

This lets a client inside WSA connect to `127.0.0.1:17890` while the server remains on Windows. The final transport is intentionally abstracted so this can later be replaced.

## Repository layout

```
windows-host/        Windows BLE bridge host
android-bridge/      WSA/Android-side bridge components
protocol/            Wire protocol specification
docs/                Architecture and roadmap
scripts/             Development/install helpers
```

## Safety and scope

This project starts read-only: passive BLE discovery only. Device connections and GATT operations are later milestones.

## Status

Early proof of concept. The Android framework/HAL is not patched yet.
