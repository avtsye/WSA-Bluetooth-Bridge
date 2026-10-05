param(
    [switch]$Resume,
    [switch]$ForceRoot
)

$ErrorActionPreference = 'Stop'

$base = Split-Path -Parent $MyInvocation.MyCommand.Path
$stateRoot = Join-Path $env:LOCALAPPDATA 'WSABluetoothBridge'
$builderRoot = Join-Path $stateRoot 'WSA-Builder'
$backupRoot = Join-Path $stateRoot 'Backups'
$logFile = Join-Path $stateRoot 'wsa-upgrade.log'
$reportFile = Join-Path $stateRoot 'root-install-report.txt'
$adb = Join-Path $base 'platform-tools\\adb.exe'

New-Item -ItemType Directory -Force $stateRoot | Out-Null
New-Item -ItemType Directory -Force $builderRoot | Out-Null
New-Item -ItemType Directory -Force $backupRoot | Out-Null
Start-Transcript -Path $logFile -Append | Out-Null
Set-Content -Path (Join-Path $stateRoot 'root-upgrade-invoked.txt') -Value ('Upgrade-Wsa invoked: ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')) -Encoding UTF8

function Test-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Restart-Elevated {
    $args = @('-ExecutionPolicy','Bypass','-NoProfile','-File',('"' + $PSCommandPath + '"'))
    if ($Resume) { $args += '-Resume' }
    if ($ForceRoot) { $args += '-ForceRoot' }
    $elevated = Start-Process powershell.exe -Verb RunAs -Wait -PassThru -ArgumentList ($args -join ' ')
    try { Stop-Transcript | Out-Null } catch {}
    exit $elevated.ExitCode
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
        [System.Windows.Forms.MessageBoxIcon]::Information
    )
    if ($choice -ne [System.Windows.Forms.DialogResult]::Yes) { throw 'המשתמש ביטל התקנת WSL.' }

    & wsl.exe --install -d Ubuntu --no-launch
    if ($LASTEXITCODE -ne 0) { throw 'התקנת WSL/Ubuntu נכשלה.' }

    $runOnce = 'powershell.exe -ExecutionPolicy Bypass -NoProfile -File "' + $PSCommandPath + '" -Resume'
    if ($ForceRoot) { $runOnce += ' -ForceRoot' }
    New-ItemProperty -Path 'HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\RunOnce' -Name 'WSABluetoothBridgeUpgrade' -Value $runOnce -PropertyType String -Force | Out-Null

    [System.Windows.Forms.MessageBox]::Show(
        'WSL הוכן. יש להפעיל מחדש את Windows; השדרוג ימשיך אוטומטית לאחר הכניסה הבאה.',
        'WSA Bluetooth Bridge',
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Information
    ) | Out-Null

    try { Stop-Transcript | Out-Null } catch {}
    exit 3010
}

function Convert-ToWslPath {
    param([string]$WindowsPath,[string]$Distro)
    $result = & wsl.exe -d $Distro -u root -- wslpath -a $WindowsPath
    if ($LASTEXITCODE -ne 0 -or -not $result) { throw 'לא ניתן להמיר נתיב Windows ל-WSL.' }
    return ($result | Select-Object -First 1).Trim()
}

function Build-RootedWsa {
    param([string]$Distro)

    $linuxBuilder = Convert-ToWslPath -WindowsPath $builderRoot -Distro $Distro
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

    $outputRoot = Join-Path $builderRoot 'MagiskOnWSALocal\\output'
    $candidate = Get-ChildItem -Path $outputRoot -Directory -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $candidate) { throw 'הבנייה הסתיימה אך לא נמצאה תיקיית output.' }

    $installScript = Join-Path $candidate.FullName 'Install.ps1'
    if (-not (Test-Path $installScript)) { throw 'תוצאת הבנייה אינה מכילה Install.ps1; WSA הקיים לא שונה.' }
    return $candidate.FullName
}

function Backup-WsaData {
    $source = Join-Path $env:LOCALAPPDATA 'Packages\\MicrosoftCorporationII.WindowsSubsystemForAndroid_8wekyb3d8bbwe\\LocalCache\\userdata.vhdx'
    if (-not (Test-Path $source)) { return $null }
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $folder = Join-Path $backupRoot $stamp
    New-Item -ItemType Directory -Force $folder | Out-Null
    $dest = Join-Path $folder 'userdata.vhdx'
    Copy-Item $source $dest -Force
    return $dest
}

function Confirm-Replacement {
    param([string]$BackupPath)
    if ($ForceRoot) { return $true }

    Add-Type -AssemblyName System.Windows.Forms
    $backupText = if ($BackupPath) { 'גיבוי נוצר ב: ' + $BackupPath } else { 'לא נמצא userdata.vhdx לגיבוי.' }
    $message = 'ה-WSA המותאם נבנה בהצלחה. כעת יש להחליף את התקנת WSA הקיימת. ' + $backupText + [Environment]::NewLine + [Environment]::NewLine + 'להמשיך בהחלפה?'
    $choice = [System.Windows.Forms.MessageBox]::Show($message,'WSA Bluetooth Bridge',[System.Windows.Forms.MessageBoxButtons]::YesNo,[System.Windows.Forms.MessageBoxIcon]::Warning)
    return $choice -eq [System.Windows.Forms.DialogResult]::Yes
}

function Write-RootReport {
    param(
        [string]$BuildFolder,
        [bool]$PackageReplaced,
        [bool]$MagiskPackagePresent,
        [bool]$SuPresent,
        [bool]$RootWorks,
        [string]$Fingerprint,
        [string]$Serial,
        [string]$InstallLocation,
        [string]$Notes
    )

    $lines = @(
        'WSA Bluetooth Bridge - Root installation report'
        ('Timestamp: ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
        ('Build folder: ' + $BuildFolder)
        ('ADB serial: ' + $Serial)
        ('WSA install location: ' + $InstallLocation)
        ('WSA package replaced: ' + $(if ($PackageReplaced) { 'YES' } else { 'NO' }))
        ('Magisk package present: ' + $(if ($MagiskPackagePresent) { 'YES' } else { 'NO' }))
        ('su present: ' + $(if ($SuPresent) { 'YES' } else { 'NO' }))
        ('root works: ' + $(if ($RootWorks) { 'YES' } else { 'NO' }))
        ('fingerprint: ' + $Fingerprint)
        ('notes: ' + $Notes)
    )
    Set-Content -Path $reportFile -Value $lines -Encoding UTF8
}

function Get-AdbWsaDevice {
    param([int]$TimeoutSeconds = 180)
    if (-not (Test-Path $adb)) { return $null }

    & $adb start-server | Out-Null
    & $adb connect 127.0.0.1:58526 2>$null | Out-Null

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        $lines = @(& $adb devices 2>$null)
        foreach ($line in $lines) {
            if ($line -match '^\\s*(\\S+)\\s+device\\s*$') {
                $serial = $matches[1]
                if ($serial -like '127.0.0.1:*' -or $serial -like 'localhost:*') { return $serial }
            }
        }
        Start-Sleep -Seconds 3
        & $adb connect 127.0.0.1:58526 2>$null | Out-Null
    }
    return $null
}

function Start-Wsa {
    $pkg = Get-AppxPackage -Name 'MicrosoftCorporationII.WindowsSubsystemForAndroid' -ErrorAction SilentlyContinue
    if (-not $pkg) { return }
    try {
        Start-Process explorer.exe 'shell:AppsFolder\\MicrosoftCorporationII.WindowsSubsystemForAndroid_8wekyb3d8bbwe!Settings' -ErrorAction SilentlyContinue | Out-Null
    } catch {}
    Start-Sleep -Seconds 5
}

function Verify-RootedWsa {
    param([string]$BuildFolder,[string]$PreviousInstallLocation)

    $pkg = Get-AppxPackage -Name 'MicrosoftCorporationII.WindowsSubsystemForAndroid' -ErrorAction SilentlyContinue
    if (-not $pkg) {
        Write-RootReport -BuildFolder $BuildFolder -PackageReplaced $false -MagiskPackagePresent $false -SuPresent $false -RootWorks $false -Fingerprint '' -Serial '' -InstallLocation '' -Notes 'WSA package is not registered after installation.'
        throw 'לא נמצאה חבילת WSA לאחר ההתקנה.'
    }

    $installLocation = [string]$pkg.InstallLocation
    $packageReplaced = $false
    if ($PreviousInstallLocation -and $installLocation) {
        $oldFull = [IO.Path]::GetFullPath($PreviousInstallLocation).TrimEnd('\\')
        $newFull = [IO.Path]::GetFullPath($installLocation).TrimEnd('\\')
        $packageReplaced = -not [string]::Equals($oldFull,$newFull,[System.StringComparison]::OrdinalIgnoreCase)
    }
    if (-not $packageReplaced -and $BuildFolder -and $installLocation) {
        $buildFull = [IO.Path]::GetFullPath($BuildFolder).TrimEnd('\\')
        $installFull = [IO.Path]::GetFullPath($installLocation).TrimEnd('\\')
        $packageReplaced = $installFull.StartsWith($buildFull,[System.StringComparison]::OrdinalIgnoreCase)
    }

    Start-Wsa
    $serial = Get-AdbWsaDevice -TimeoutSeconds 180
    if (-not $serial) {
        Write-RootReport -BuildFolder $BuildFolder -PackageReplaced $packageReplaced -MagiskPackagePresent $false -SuPresent $false -RootWorks $false -Fingerprint '' -Serial '' -InstallLocation $installLocation -Notes 'WSA registered, but ADB did not come online.'
        throw 'WSA הותקן, אך לא עלה ב-ADB לצורך אימות Root.'
    }

    $fingerprint = ((& $adb -s $serial shell getprop ro.build.fingerprint 2>$null | Select-Object -First 1) | Out-String).Trim()
    $suPath = ((& $adb -s $serial shell 'command -v su' 2>$null | Select-Object -First 1) | Out-String).Trim()
    $suPresent = -not [string]::IsNullOrWhiteSpace($suPath)

    $packageLines = @(& $adb -s $serial shell 'pm list packages' 2>$null)
    $magiskPackagePresent = @($packageLines | Where-Object { $_ -match '(?i)magisk' }).Count -gt 0
    $magiskCmd = ((& $adb -s $serial shell 'command -v magisk' 2>$null | Select-Object -First 1) | Out-String).Trim()
    if (-not [string]::IsNullOrWhiteSpace($magiskCmd)) { $magiskPackagePresent = $true }

    $rootText = ''
    $rootWorks = $false
    if ($suPresent) {
        $rootText = (& $adb -s $serial shell su -c id 2>&1 | Out-String).Trim()
        $rootWorks = $rootText -match 'uid=0'
    }

    $notes = if ($rootWorks) { 'Root verification passed.' } else { 'Root verification failed. su output: ' + $rootText }
    Write-RootReport -BuildFolder $BuildFolder -PackageReplaced $packageReplaced -MagiskPackagePresent $magiskPackagePresent -SuPresent $suPresent -RootWorks $rootWorks -Fingerprint $fingerprint -Serial $serial -InstallLocation $installLocation -Notes $notes

    if (-not $packageReplaced) { throw ('WSA החדש נרשם, אך לא הצלחתי לאמת שהחבילה הישנה הוחלפה. ראה: ' + $reportFile) }
    if (-not $magiskPackagePresent) { throw ('WSA הותקן אך Magisk לא זוהה. ראה: ' + $reportFile) }
    if (-not $suPresent) { throw ('WSA הותקן אך su לא נמצא. ראה: ' + $reportFile) }
    if (-not $rootWorks) { throw ('su נמצא אך Root אינו פעיל. ראה: ' + $reportFile) }
    return $true
}

function Install-CustomWsa {
    param([string]$BuildFolder,[string]$BackupPath,[string]$PreviousInstallLocation)

    if (-not (Test-Administrator)) { throw 'שלב החלפת WSA דורש הרשאת מנהל.' }

    Get-Process -Name 'WsaClient','WsaService','WsaSettings' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2

    $pkg = Get-AppxPackage -Name 'MicrosoftCorporationII.WindowsSubsystemForAndroid' -ErrorAction SilentlyContinue
    if ($pkg) { $pkg | Remove-AppxPackage -ErrorAction Stop }

    $installScript = Join-Path $BuildFolder 'Install.ps1'
    & powershell.exe -ExecutionPolicy Bypass -NoProfile -File $installScript
    if ($LASTEXITCODE -ne 0) { throw 'התקנת WSA המותאם נכשלה.' }

    if ($BackupPath -and (Test-Path $BackupPath)) {
        $targetDir = Join-Path $env:LOCALAPPDATA 'Packages\\MicrosoftCorporationII.WindowsSubsystemForAndroid_8wekyb3d8bbwe\\LocalCache'
        New-Item -ItemType Directory -Force $targetDir | Out-Null
        Copy-Item $BackupPath (Join-Path $targetDir 'userdata.vhdx') -Force
    }

    Verify-RootedWsa -BuildFolder $BuildFolder -PreviousInstallLocation $PreviousInstallLocation | Out-Null
}

try {
    if (-not (Test-Administrator)) { Restart-Elevated }

    $distro = Ensure-Wsl
    $buildFolder = Build-RootedWsa -Distro $distro
    $backup = Backup-WsaData
    $oldPkg = Get-AppxPackage -Name 'MicrosoftCorporationII.WindowsSubsystemForAndroid' -ErrorAction SilentlyContinue
    $oldInstallLocation = if ($oldPkg) { [string]$oldPkg.InstallLocation } else { '' }

    if (-not (Confirm-Replacement -BackupPath $backup)) {
        Write-Host 'החלפת WSA בוטלה. הבנייה והגיבוי נשמרו.'
        try { Stop-Transcript | Out-Null } catch {}
        exit 20
    }

    Install-CustomWsa -BuildFolder $buildFolder -BackupPath $backup -PreviousInstallLocation $oldInstallLocation
    Write-Host ('WSA מותאם עם Magisk הותקן ואומת בהצלחה. דוח: ' + $reportFile)
    try { Stop-Transcript | Out-Null } catch {}
    exit 0
}
catch {
    $message = ($_ | Out-String).Trim()
    Write-Host ''
    Write-Host '============================================' -ForegroundColor Red
    Write-Host 'WSA Bluetooth Bridge - ROOT UPGRADE FAILED' -ForegroundColor Red
    Write-Host '============================================' -ForegroundColor Red
    Write-Host $message -ForegroundColor Red
    Write-Host ''
    Write-Host ('Log: ' + $logFile) -ForegroundColor Yellow
    Write-Host ('Report: ' + $reportFile) -ForegroundColor Yellow
    Write-Host ''
    try { Stop-Transcript | Out-Null } catch {}
    [void](Read-Host 'השגיאה נשארת פתוחה. לחץ Enter רק לאחר שהעתקת/צילמת אותה')
    exit 1
}
