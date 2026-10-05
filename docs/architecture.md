# Architecture

## Objective

Expose Windows Bluetooth to Android running in WSA without requiring Android applications to know about the bridge.

## Development architecture

```
Android test client
        |
        | 127.0.0.1:17890
        | (adb reverse during PoC)
        v
WsaBluetoothHost.exe
        |
        v
Windows.Devices.Bluetooth
        |
        v
Windows Bluetooth stack
```

This development client is **not** the final integration point.

## Target architecture

```
Android application
        |
Android Bluetooth framework
        |
custom WSA Bluetooth backend/HAL
        |
bridge transport
        |
Windows Bluetooth host
        |
Windows Bluetooth stack
```

The transport and Bluetooth implementation are deliberately separated. This allows the temporary TCP/ADB transport to be replaced without rewriting the Bluetooth logic.

## Milestones

1. Windows BLE scan.
2. Transfer scan results into WSA.
3. Android-side privileged bridge service.
4. Framework/HAL integration so normal `BluetoothLeScanner` calls reach the bridge.
5. BLE connect/disconnect.
6. GATT service discovery.
7. GATT read/write.
8. Notifications/indications.
9. Pairing/bonding if required.
10. Evaluate Bluetooth Classic separately.
