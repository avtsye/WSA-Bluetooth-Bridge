$ErrorActionPreference = 'Stop'

$base = Split-Path -Parent $MyInvocation.MyCommand.Path
$adb = Join-Path $base 'platform-tools\adb.exe'
$module = Join-Path $base 'wsa-system-module.zip'

if (-not (Test-Path $adb)) {
    Write-Host 'ADB לא נמצא בחבילת ההתקנה.'
    exit 2
}

& $adb start-server | Out-Null
$devices = & $adb devices
$online = $devices | Select-String 'device$'
if (-not $online) {
    Write-Host 'WSA אינו מחובר כרגע דרך ADB. ניתן להריץ את ההתקנה שוב מאוחר יותר.'
    exit 3
}

& $adb push $module /data/local/tmp/wsa-system-module.zip
if ($LASTEXITCODE -ne 0) {
    throw 'העתקת מודול WSA נכשלה.'
}

$root = & $adb shell su -c id 2>&1
if ($LASTEXITCODE -ne 0 -or $root -notmatch 'uid=0') {
    Write-Host 'ל-WSA אין כרגע הרשאת root/Magisk. ה-Host של Windows הותקן, אך רכיב המערכת לא הוזרק.'
    exit 4
}

$magisk = & $adb shell su -c 'command -v magisk' 2>&1
if ($LASTEXITCODE -eq 0 -and $magisk) {
    & $adb shell su -c 'magisk --install-module /data/local/tmp/wsa-system-module.zip'
    if ($LASTEXITCODE -eq 0) {
        Write-Host 'מודול WSA הותקן. יש להפעיל מחדש את WSA/Android כדי להפעילו.'
        exit 0
    }
}

Write-Host 'נמצאה הרשאת root אך לא נמצאה התקנת Magisk תואמת. המודול נשמר ב-/data/local/tmp.'
exit 5
