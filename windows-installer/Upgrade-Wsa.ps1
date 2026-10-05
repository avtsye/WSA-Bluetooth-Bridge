$ErrorActionPreference = 'Stop'

param(
    [switch]$Resume
)

$base = Split-Path -Parent $MyInvocation.MyCommand.Path
$stateRoot = Join-Path $env:LOCALAPPDATA 'WSABluetoothBridge'
$builderRoot = Join-Path $stateRoot 'WSA-Builder'
$backupRoot = Join-Path $stateRoot 'Backups'
$logFile = Join-Path $stateRoot 'wsa-upgrade.log'

New-Item -ItemType Directory -Force $stateRoot | Out-Null
New-Item -ItemType Directory -Force $builderRoot | Out-Null
New-Item -ItemType Directory -Force $backupRoot | Out-Null

Start-Transcript -Path $logFile -Append | Out-Null

function Test-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Restart-Elevated {
    $args = @('-ExecutionPolicy','Bypass','-NoProfile','-File',('"' + $PSCommandPath + '"'))
    if ($Resume) { $args += '-Resume' }
    Start-Process powershell.exe -Verb RunAs -ArgumentList ($args -join ' ')
    Stop-Transcript | Out-Null
    exit 0
}

function Get-WslDistro {
    $items = @(& wsl.exe -l -q 2>$null | ForEach-Object { $_.Trim([char]0).Trim() } | Where-Object { $_ })
    if ($items.Count -eq 0) { return $null }
    $preferred = @($items | Where-Object { $_ -match 'Ubuntu|Debian' })
    if ($preferred.Count -gt 0) { return $preferred[0] }
    return $items[0]
}

function Ensure-Wsl {
    $distro = Get-WslDistro
    if ($distro) { return $distro }

    if (-not (Test-Administrator)) { Restart-Elevated }

    Add-Type -AssemblyName System.Windows.Forms
    $choice = [System.Windows.Forms.MessageBox]::Show(
        'כדי לבנות WSA מותאם נדרש WSL. המתקין יכול להתקין Ubuntu עבור התהליך. ייתכן שיידרש אתחול של Windows. להמשיך?',
        'WSA Bluetooth Bridge',
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Information)

    if ($choice -ne [System.Windows.Forms.DialogResult]::Yes) {
        throw 'המשתמש ביטל התקנת WSL.'
    }

    & wsl.exe --install -d Ubuntu --no-launch
    if ($LASTEXITCODE -ne 0) {
        throw 'התקנת WSL/Ubuntu נכשלה.'
    }

    $runOnce = 'powershell.exe -ExecutionPolicy Bypass -NoProfile -File "' + $PSCommandPath + '" -Resume'
    New-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce' -Name 'WSABluetoothBridgeUpgrade' -Value $runOnce -PropertyType String -Force | Out-Null

    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.MessageBox]::Show(
        'WSL הוכן. יש להפעיל מחדש את Windows; השדרוג ימשיך אוטומטית לאחר הכניסה הבאה.',
        'WSA Bluetooth Bridge',
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null

    Stop-Transcript | Out-Null
    exit 3010
}

function Convert-ToWslPath([string]$WindowsPath, [string]$Distro) {
    $result = & wsl.exe -d $Distro -u root -- wslpath -a $WindowsPath
    if ($LASTEXITCODE -ne 0 -or -not $result) { throw 'לא ניתן להמיר נתיב Windows ל-WSL.' }
    return ($result | Select-Object -First 1).Trim()
}

function Build-RootedWsa([string]$Distro) {
    $linuxBuilder = Convert-ToWslPath $builderRoot $Distro

    $bootstrap = 'export DEBIAN_FRONTEND=noninteractive; apt-get update; apt-get install -y git ca-certificates curl python3 aria2 unzip whiptail python3-venv python3-pip p7zip-full; mkdir -p ' + "'" + $linuxBuilder + "'"
    & wsl.exe -d $Distro -u root -- bash -lc $bootstrap
    if ($LASTEXITCODE -ne 0) { throw 'הכנת סביבת הבנייה ב-WSL נכשלה.' }

    $repoLinux = $linuxBuilder + '/MagiskOnWSALocal'
    $clone = 'if [ -d ' + "'" + $repoLinux + '/.git' + "'" + ' ]; then git -C ' + "'" + $repoLinux + "'" + ' pull --ff-only; else git clone --depth 1 https://github.com/LSPosed/MagiskOnWSALocal.git ' + "'" + $repoLinux + "'" + '; fi'
    & wsl.exe -d $Distro -u root -- bash -lc $clone
    if ($LASTEXITCODE -ne 0) { throw 'הורדת כלי בניית WSA נכשלה.' }

    $build = 'cd ' + "'" + $repoLinux + '/scripts' + "'" + '; chmod +x install_deps.sh build.sh; ./install_deps.sh; ./build.sh --arch x64 --release-type retail --root-sol magisk --magisk-ver stable --compress-format none'
    & wsl.exe -d $Distro -u root -- bash -lc $build
    if ($LASTEXITCODE -ne 0) { throw 'בניית WSA עם Magisk נכשלה. ה-WSA הקיים לא שונה.' }

    $outputRoot = Join-Path $builderRoot 'MagiskOnWSALocal\output'
    $candidate = Get-ChildItem -Path $outputRoot -Directory -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $candidate) { throw 'הבנייה הסתיימה אך לא נמצאה תיקיית output.' }

    $installScript = Join-Path $candidate.FullName 'Install.ps1'
    if (-not (Test-Path $installScript)) { throw 'תוצאת הבנייה אינה מכילה Install.ps1; WSA הקיים לא שונה.' }

    return $candidate.FullName
}

function Backup-WsaData {
    $source = Join-Path $env:LOCALAPPDATA 'Packages\MicrosoftCorporationII.WindowsSubsystemForAndroid_8wekyb3d8bbwe\LocalCache\userdata.vhdx'
    if (-not (Test-Path $source)) { return $null }

    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $folder = Join-Path $backupRoot $stamp
    New-Item -ItemType Directory -Force $folder | Out-Null
    $dest = Join-Path $folder 'userdata.vhdx'
    Copy-Item $source $dest -Force
    return $dest
}

function Confirm-Replacement([string]$BackupPath) {
    Add-Type -AssemblyName System.Windows.Forms
    $backupText = if ($BackupPath) { 'גיבוי נוצר ב: ' + $BackupPath } else { 'לא נמצא userdata.vhdx לגיבוי.' }
    $message = 'ה-WSA המותאם נבנה בהצלחה. כעת יש להחליף את התקנת WSA הקיימת. ' + $backupText + [Environment]::NewLine + [Environment]::NewLine + 'להמשיך בהחלפה?'
    $choice = [System.Windows.Forms.MessageBox]::Show($message,'WSA Bluetooth Bridge',[System.Windows.Forms.MessageBoxButtons]::YesNo,[System.Windows.Forms.MessageBoxIcon]::Warning)
    return $choice -eq [System.Windows.Forms.DialogResult]::Yes
}

function Install-CustomWsa([string]$BuildFolder, [string]$BackupPath) {
    if (-not (Test-Administrator)) {
        throw 'שלב החלפת WSA דורש הרשאת מנהל.'
    }

    Get-Process -Name 'WsaClient','WsaService','WsaSettings' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2

    $pkg = Get-AppxPackage -Name 'MicrosoftCorporationII.WindowsSubsystemForAndroid' -ErrorAction SilentlyContinue
    if ($pkg) {
        $pkg | Remove-AppxPackage -ErrorAction Stop
    }

    $installScript = Join-Path $BuildFolder 'Install.ps1'
    & powershell.exe -ExecutionPolicy Bypass -NoProfile -File $installScript
    if ($LASTEXITCODE -ne 0) { throw 'התקנת WSA המותאם נכשלה.' }

    if ($BackupPath -and (Test-Path $BackupPath)) {
        $targetDir = Join-Path $env:LOCALAPPDATA 'Packages\MicrosoftCorporationII.WindowsSubsystemForAndroid_8wekyb3d8bbwe\LocalCache'
        New-Item -ItemType Directory -Force $targetDir | Out-Null
        Copy-Item $BackupPath (Join-Path $targetDir 'userdata.vhdx') -Force
    }
}

try {
    if (-not (Test-Administrator)) { Restart-Elevated }

    $distro = Ensure-Wsl
    $buildFolder = Build-RootedWsa $distro
    $backup = Backup-WsaData

    if (-not (Confirm-Replacement $backup)) {
        Write-Host 'החלפת WSA בוטלה. הבנייה והגיבוי נשמרו.'
        Stop-Transcript | Out-Null
        exit 20
    }

    Install-CustomWsa $buildFolder $backup
    Write-Host 'WSA מותאם עם Magisk הותקן בהצלחה.'
    Stop-Transcript | Out-Null
    exit 0
}
catch {
    Write-Error $_
    try { Stop-Transcript | Out-Null } catch {}
    exit 1
}