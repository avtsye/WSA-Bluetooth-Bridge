$ErrorActionPreference = 'Stop'

$base = Split-Path -Parent $MyInvocation.MyCommand.Path
$adb = Join-Path $base 'platform-tools\adb.exe'
$module = Join-Path $base 'wsa-system-module.zip'
$apk = Join-Path $base 'WsaBluetoothBridgeClient.apk'

$installLogRoot = Join-Path $env:ProgramData 'WSABluetoothBridge'
New-Item -ItemType Directory -Force $installLogRoot | Out-Null
$installLogFile = Join-Path $installLogRoot 'android-integration.log'
Start-Transcript -Path $installLogFile -Append | Out-Null

function Exit-WithStatus {
    param([int]$Code)

    if ($Code -ne 0) {
        Write-Host ''
        Write-Host '============================================' -ForegroundColor Red
        Write-Host 'WSA Bluetooth Bridge - INSTALLATION FAILED' -ForegroundColor Red
        Write-Host '============================================' -ForegroundColor Red
        Write-Host ('Exit code: ' + $Code) -ForegroundColor Red
        Write-Host ('Log: ' + $installLogFile) -ForegroundColor Yellow
        Write-Host ''
        try { Stop-Transcript | Out-Null } catch {}
        [void](Read-Host 'השגיאה נשארת פתוחה. לחץ Enter רק לאחר שהעתקת/צילמת אותה')
    }
    else {
        try { Stop-Transcript | Out-Null } catch {}
    }

    exit $Code
}


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
    Exit-WithStatus 2
}

if (-not (Test-Path $module)) {
    Write-Host 'מודול המערכת של WSA חסר בחבילת ההתקנה.'
    Exit-WithStatus 6
}

if (-not (Test-Path $apk)) {
    Write-Host 'קובץ ה-APK חסר בחבילת ההתקנה.'
    Exit-WithStatus 7
}

& $adb start-server | Out-Null
$serial = Get-WsaDevice -TimeoutSeconds 120

if (-not $serial) {
    Write-Host 'WSA לא הופיע ב-ADB בתוך 120 שניות. רכיב Windows הותקן, אך צד Android לא הותקן.'
    Exit-WithStatus 3
}

Write-Host "WSA/Android נמצא: $serial"

# Install/update the diagnostic Android application automatically.
& $adb -s $serial install -r $apk
if ($LASTEXITCODE -ne 0) {
    Write-Host 'התקנת אפליקציית Android נכשלה.'
    Exit-WithStatus 8
}

# The Windows host performs adb reverse continuously, but configure it once here too
# so the freshly installed Android side can work immediately.
& $adb -s $serial reverse tcp:17890 tcp:17890 | Out-Null
& $adb -s $serial reverse tcp:17891 tcp:17891 | Out-Null

# Copy the system module into Android.
& $adb -s $serial push $module /data/local/tmp/wsa-system-module.zip
if ($LASTEXITCODE -ne 0) {
    Write-Host 'העתקת מודול WSA נכשלה.'
    Exit-WithStatus 9
}

# Full system integration requires root/Magisk in WSA.
$root = & $adb -s $serial shell su -c id 2>&1
if ($LASTEXITCODE -ne 0 -or $root -notmatch 'uid=0') {
    Write-Host 'ל-WSA אין root/Magisk. מפעיל את מסייע השדרוג הבטוח...'
    $upgrade = Join-Path $base 'Upgrade-Wsa.ps1'
    if (-not (Test-Path $upgrade)) {
        Write-Host 'קובץ Upgrade-Wsa.ps1 חסר.'
        Exit-WithStatus 4
    }

    $upgradeProcess = Start-Process powershell.exe -Verb RunAs -Wait -PassThru -ArgumentList @(
        '-ExecutionPolicy','Bypass','-NoProfile','-File',('"' + $upgrade + '"'),'-ForceRoot'
    )

    if ($upgradeProcess.ExitCode -ne 0) {
        Write-Host ('שדרוג WSA עם Root/Magisk לא הושלם. קוד יציאה: ' + $upgradeProcess.ExitCode)
        Exit-WithStatus 4
    }

    & $adb start-server | Out-Null
    & $adb connect 127.0.0.1:58526 2>$null | Out-Null
    Start-Sleep -Seconds 5
    $serial = Get-WsaDevice -TimeoutSeconds 120
    if (-not $serial) {
        Write-Host 'WSA המותאם הותקן, אך הוא עדיין לא הופיע ב-ADB.'
        Exit-WithStatus 11
    }

    & $adb -s $serial install -r $apk
    & $adb -s $serial reverse tcp:17890 tcp:17890 | Out-Null
    & $adb -s $serial reverse tcp:17891 tcp:17891 | Out-Null
    & $adb -s $serial push $module /data/local/tmp/wsa-system-module.zip

    $root = & $adb -s $serial shell su -c id 2>&1
    if ($LASTEXITCODE -ne 0 -or $root -notmatch 'uid=0') {
        Write-Host 'השדרוג הסתיים אך root עדיין אינו זמין.'
        Exit-WithStatus 12
    }
}

$magisk = & $adb -s $serial shell su -c 'command -v magisk' 2>&1
if ($LASTEXITCODE -ne 0 -or -not $magisk) {
    Write-Host 'נמצאה הרשאת root, אך Magisk לא נמצא.'
    Exit-WithStatus 5
}

& $adb -s $serial shell su -c 'magisk --install-module /data/local/tmp/wsa-system-module.zip'
if ($LASTEXITCODE -ne 0) {
    Write-Host 'התקנת מודול המערכת דרך Magisk נכשלה.'
    Exit-WithStatus 10
}

Write-Host 'מודול המערכת הותקן. מאתחל את צד Android כדי להפעיל את האינטגרציה העמוקה...'
& $adb -s $serial shell su -c reboot 2>$null | Out-Null
Start-Sleep -Seconds 8

& $adb start-server | Out-Null
& $adb connect 127.0.0.1:58526 2>$null | Out-Null
$serial = Get-WsaDevice -TimeoutSeconds 180

if (-not $serial) {
    Write-Host 'המודול הותקן, אך WSA לא חזר ל-ADB לאחר האתחול. הוא אמור לעלות עם המודול באתחול הבא.'
    Exit-WithStatus 13
}

& $adb -s $serial reverse tcp:17890 tcp:17890 | Out-Null
& $adb -s $serial reverse tcp:17891 tcp:17891 | Out-Null

$logRoot = Join-Path $env:LOCALAPPDATA 'WSABluetoothBridge'
New-Item -ItemType Directory -Force $logRoot | Out-Null

Start-Sleep -Seconds 5

$audioEnv = Join-Path $logRoot 'wsa-bt-audio-env.txt'
$systemStatus = Join-Path $logRoot 'wsa-bt-system-status.json'

& $adb -s $serial shell su -c '/data/adb/modules/wsa_bt_bridge/audio-env.sh' 2>$null | Out-Null
& $adb -s $serial pull /data/local/tmp/wsa-bt-audio-env.txt $audioEnv 2>$null | Out-Null
& $adb -s $serial pull /data/local/tmp/wsa-bt-system-status.json $systemStatus 2>$null | Out-Null

if (Test-Path $audioEnv) {
    Write-Host ('אבחון Audio HAL נשמר ב: ' + $audioEnv)
}

if (Test-Path $systemStatus) {
    Write-Host ('סטטוס רכיב המערכת נשמר ב: ' + $systemStatus)
}

$policyState = Join-Path $logRoot 'wsa-bt-policy-state.json'
& $adb -s $serial pull /data/local/tmp/wsa-bt-policy-state.json $policyState 2>$null | Out-Null

$activatePolicy = $false
if (Test-Path $policyState) {
    try {
        $policy = Get-Content $policyState -Raw | ConvertFrom-Json
        if ($policy.compatible -eq $true -and $policy.enabled -ne $true) {
            $activatePolicy = $true
        }
    }
    catch {
        Write-Host 'לא ניתן לקרוא את מצב Audio Policy; נשאר במצב אבחון בטוח.'
    }
}

if ($activatePolicy) {
    Write-Host 'Audio HAL תואם נמצא. מפעיל את נתיב WSA Bridge ומאתחל את Android פעם נוספת...'

    & $adb -s $serial shell su -c '/data/adb/modules/wsa_bt_bridge/enable-policy.sh' 2>$null | Out-Null
    & $adb -s $serial shell su -c '/data/adb/modules/wsa_bt_bridge/policy-shim.sh' 2>$null | Out-Null

    & $adb -s $serial shell su -c reboot 2>$null | Out-Null
    Start-Sleep -Seconds 8

    & $adb start-server | Out-Null
    & $adb connect 127.0.0.1:58526 2>$null | Out-Null
    $serial = Get-WsaDevice -TimeoutSeconds 180

    if (-not $serial) {
        Write-Host 'WSA לא חזר לאחר הפעלת Audio Policy. המודול כולל rollback ויחזור למצב בטוח באתחול הבא.'
        Exit-WithStatus 14
    }

    & $adb -s $serial reverse tcp:17890 tcp:17890 | Out-Null
    & $adb -s $serial reverse tcp:17891 tcp:17891 | Out-Null
    Start-Sleep -Seconds 10

    $health = Join-Path $logRoot 'wsa-bt-health.json'
    $policyState2 = Join-Path $logRoot 'wsa-bt-policy-state-after-activation.json'

    & $adb -s $serial shell su -c '/data/adb/modules/wsa_bt_bridge/health-check.sh' 2>$null | Out-Null
    & $adb -s $serial pull /data/local/tmp/wsa-bt-health.json $health 2>$null | Out-Null
    & $adb -s $serial pull /data/local/tmp/wsa-bt-policy-state.json $policyState2 2>$null | Out-Null

    if (Test-Path $health) {
        try {
            $healthInfo = Get-Content $health -Raw | ConvertFrom-Json
            if ($healthInfo.healthy -ne $true) {
                Write-Host 'בדיקת AudioFlinger נכשלה. rollback הוכן אוטומטית.'
                & $adb -s $serial shell su -c reboot 2>$null | Out-Null
                Exit-WithStatus 15
            }
            Write-Host 'Audio HAL/Policy shim פעיל ובריא.'
        }
        catch {
            Write-Host 'לא ניתן לאמת את קובץ הבריאות; הלוג נשמר לבדיקה.'
        }
    }
}
else {
    Write-Host 'Audio Policy נשאר במצב אבחון: לא זוהתה עדיין תאימות בטוחה להפעלה.'
}

Write-Host 'התקנת Windows + Android + Audio HAL bridge הושלמה.'
Exit-WithStatus 0
