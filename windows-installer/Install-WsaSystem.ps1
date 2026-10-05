$ErrorActionPreference = 'Stop'

$base = Split-Path -Parent $MyInvocation.MyCommand.Path
$adb = Join-Path $base 'platform-tools\adb.exe'
$module = Join-Path $base 'wsa-system-module.zip'
$apk = Join-Path $base 'WsaBluetoothBridgeClient.apk'

function Get-WsaDevice {
    param([int]$TimeoutSeconds = 120)

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)

    while ((Get-Date) -lt $deadline) {
        $lines = & $adb devices 2>$null
        $devices = @()

        foreach ($line in $lines) {
            if ($line -match '^\s*(\S+)\s+device\s*$') {
                $devices += $matches[1]
            }
        }

        if ($devices.Count -gt 0) {
            $network = @($devices | Where-Object {
                $_ -match ':' -or $_ -like '127.0.0.1*' -or $_ -like 'localhost*'
            })

            if ($network.Count -gt 0) {
                return $network[0]
            }

            return $devices[0]
        }

        Start-Sleep -Seconds 2
    }

    return $null
}

if (-not (Test-Path $adb)) {
    Write-Host 'ADB לא נמצא בחבילת ההתקנה.'
    exit 2
}

if (-not (Test-Path $module)) {
    Write-Host 'מודול המערכת של WSA חסר בחבילת ההתקנה.'
    exit 6
}

if (-not (Test-Path $apk)) {
    Write-Host 'קובץ ה-APK חסר בחבילת ההתקנה.'
    exit 7
}

& $adb start-server | Out-Null
$serial = Get-WsaDevice -TimeoutSeconds 120

if (-not $serial) {
    Write-Host 'WSA לא הופיע ב-ADB בתוך 120 שניות. רכיב Windows הותקן, אך צד Android לא הותקן.'
    exit 3
}

Write-Host "WSA/Android נמצא: $serial"

# Install/update the diagnostic Android application automatically.
& $adb -s $serial install -r $apk
if ($LASTEXITCODE -ne 0) {
    Write-Host 'התקנת אפליקציית Android נכשלה.'
    exit 8
}

# The Windows host performs adb reverse continuously, but configure it once here too
# so the freshly installed Android side can work immediately.
& $adb -s $serial reverse tcp:17890 tcp:17890 | Out-Null
& $adb -s $serial reverse tcp:17891 tcp:17891 | Out-Null

# Copy the system module into Android.
& $adb -s $serial push $module /data/local/tmp/wsa-system-module.zip
if ($LASTEXITCODE -ne 0) {
    Write-Host 'העתקת מודול WSA נכשלה.'
    exit 9
}

# Full system integration requires root/Magisk in WSA.
$root = & $adb -s $serial shell su -c id 2>&1
if ($LASTEXITCODE -ne 0 -or $root -notmatch 'uid=0') {
    Write-Host 'האפליקציה הותקנה, אך ל-WSA אין root/Magisk ולכן לא ניתן להתקין את רכיב המערכת העמוק.'
    exit 4
}

$magisk = & $adb -s $serial shell su -c 'command -v magisk' 2>&1
if ($LASTEXITCODE -ne 0 -or -not $magisk) {
    Write-Host 'נמצאה הרשאת root, אך Magisk לא נמצא. האפליקציה הותקנה אך מודול המערכת לא הותקן.'
    exit 5
}

& $adb -s $serial shell su -c 'magisk --install-module /data/local/tmp/wsa-system-module.zip'
if ($LASTEXITCODE -ne 0) {
    Write-Host 'התקנת מודול המערכת דרך Magisk נכשלה.'
    exit 10
}

Write-Host 'התקנת Windows + Android + מודול המערכת הושלמה בהצלחה.'
exit 0
