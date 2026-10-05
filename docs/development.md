# Development: first end-to-end BLE scan

## Requirements

- Windows 11 with Bluetooth enabled.
- WSA installed and ADB access enabled.
- .NET 8 SDK if building the Windows host locally.
- Android SDK/Gradle if building the test APK locally.

## 1. Build and start the Windows host

From the repository root:

```powershell
dotnet run --project .\windows-host\WsaBluetoothHost.csproj
```

Expected output:

```text
WSA Bluetooth Host listening on 127.0.0.1:17890
```

## 2. Connect ADB to WSA

Use the ADB endpoint shown by WSA developer settings, then:

```powershell
adb connect <WSA-IP:PORT>
```

## 3. Create the temporary development tunnel

```powershell
adb reverse tcp:17890 tcp:17890
```

This is intentionally temporary. It proves transport without requiring a permanent network listener on Windows.

## 4. Build/install the test client

```powershell
cd android-bridge
gradle assembleDebug
adb install -r .\app\build\outputs\apk\debug\app-debug.apk
```

Alternatively use the APK produced by the GitHub Actions artifact.

## 5. Test

Open **WSA Bluetooth Bridge Client** inside WSA.

1. Select **Connect to Windows host**.
2. Verify a `hello` packet appears.
3. Select **Start BLE scan**.
4. Nearby BLE advertisements should begin appearing with address, RSSI, name when advertised, and service UUIDs.

## What success means

Success at this stage proves:

- Windows can perform the BLE scan.
- WSA can communicate with the bridge.
- BLE discovery events survive the bridge protocol.

It does **not** yet mean Android's normal `BluetoothAdapter`/`BluetoothLeScanner` APIs work. That is the next integration milestone.
