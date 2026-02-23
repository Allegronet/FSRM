#requires -version 3.0
#requires -runasadministrator
<#
  FSRM Crypto Extensions Auto-Update + Block Template + Screens + Weekly Task
  Author: edk
  PS: 3.0+

  Usage:
    1) First install/run:
       powershell.exe -ExecutionPolicy Bypass -File .\FSRM-CryptoWall-AllInOne.ps1

    2) Update only (used by scheduled task):
       powershell.exe -ExecutionPolicy Bypass -File .\FSRM-CryptoWall-AllInOne.ps1 -UpdateOnly
#>

param(
    [switch]$UpdateOnly
)

$ErrorActionPreference = "Stop"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# ================== CONFIG ==================
$GroupName     = "CryptoWall File Monitor"
$TemplateName  = "CryptoWall Block Template"

# URL with patterns
$PatternsUrl   = "https://raw.githubusercontent.com/Allegronet/FSRM/refs/heads/main/fsrm-block-lost.txt"

# Logging / scripts dirs
$TaskScriptsDir = "C:\TaskScripts"
$TaskLogsDir    = "C:\TaskLogs"
$ErrLog         = Join-Path $TaskLogsDir "FSRM-Error.log"
$InfoLog        = Join-Path $TaskLogsDir "FSRM-Info.log"

# SMTP + admin mail
$SmtpServer = "smtp.allegronet.co.il"
$AdminEmail = "noc@allegronet.co.il"

# Apply File Screen to these folders (EDIT THIS!)
$TargetPaths = @(
    "D:\Shares"         # <--- CHANGE ME
    # "E:\Data"
)

# Scheduled task
$TaskName = "FSRM weekly update Crypto extensions"
$RunDay   = "Sunday"
$RunAt    = "09:00"
# ===========================================

function Ensure-Dir([string]$Path) {
    if (-not (Test-Path $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Log-Info([string]$Msg) {
    ("{0} | {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Msg) |
        Out-File $InfoLog -Append -Encoding UTF8
}

function Log-Err([object]$ErrObj) {
    ("{0} | {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), ($ErrObj | Out-String)) |
        Out-File $ErrLog -Append -Encoding UTF8
}

function Require-FsrmModule {
    try {
        Import-Module FileServerResourceManager -ErrorAction Stop
    } catch {
        throw "FileServerResourceManager module not available. Install FSRM feature and PowerShell module."
    }
}

function Download-Patterns([string]$Url) {
    $raw = (Invoke-WebRequest -Uri $Url -UseBasicParsing).Content

    # Trim, skip empty and comments
    $patterns = $raw -split "`r?`n" |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ -ne "" -and -not $_.StartsWith("#") }

    # unique
    $patterns = $patterns | Sort-Object -Unique

    return $patterns
}

function Ensure-FileGroup([string]$Name) {
    $g = Get-FsrmFileGroup -Name $Name -ErrorAction SilentlyContinue
    if (-not $g) {
        # anchor
        New-FsrmFileGroup -Name $Name -IncludePattern @("*.tmp") | Out-Null
        Log-Info "Created File Group: $Name (anchor *.tmp)"
    } else {
        Log-Info "File Group exists: $Name"
    }
}

function Update-FileGroupPatterns([string]$Name, [string[]]$Patterns) {
    # This is the code you requested (wrapped with logging + stop on error)
    Set-FsrmFileGroup -Name $Name -IncludePattern $Patterns
    Log-Info ("Updated File Group '{0}' patterns={1}" -f $Name, $Patterns.Count)
}

function Ensure-FsrmNotifications {
    # global settings
    Set-FsrmSetting -SmtpServer $SmtpServer -AdminEmailAddress $AdminEmail
    Log-Info "FSRM SMTP set: $SmtpServer ; AdminEmail: $AdminEmail"
}

function Ensure-Template([string]$Template, [string]$Group) {
    $t = Get-FsrmFileScreenTemplate -Name $Template -ErrorAction SilentlyContinue
    if (-not $t) {
        $mail = New-FsrmAction -Type Email `
            -MailTo "[Admin Email]" `
            -Subject "Unauthorized file matching [Violated File Group] detected" `
            -Body "The system detected that user [Source Io Owner] attempted to save [Source File Path] on [File Screen Path] on server [Server]. This file matches [Violated File Group] which is not permitted." `
            -RunLimitInterval 120

        $evt = New-FsrmAction -Type Event `
            -EventType Information `
            -Body "FSRM blocked: user [Source Io Owner] file [Source File Path] share [File Screen Path] server [Server] group [Violated File Group]." `
            -RunLimitInterval 180

        New-FsrmFileScreenTemplate -Name $Template -IncludeGroup $Group -Notification @($mail, $evt) -Active | Out-Null
        Log-Info "Created File Screen Template: $Template (group=$Group)"
    } else {
        Log-Info "Template exists: $Template"
    }
}

function Ensure-FileScreens([string[]]$Paths, [string]$Template) {
    foreach ($p in $Paths) {
        if (-not (Test-Path $p)) {
            Log-Info "WARNING: TargetPath not found, skipping: $p"
            continue
        }

        $screen = Get-FsrmFileScreen -Path $p -ErrorAction SilentlyContinue
        if (-not $screen) {
            New-FsrmFileScreen -Path $p -Template $Template | Out-Null
            Log-Info "Applied File Screen: path=$p template=$Template"
        } else {
            Log-Info "File Screen exists: $p"
        }
    }
}

function Ensure-WeeklyTask([string]$ScriptFullPath) {
    # If ScheduledTasks module isn't available on this OS, fallback to schtasks
    $hasScheduledTasks = $false
    try {
        Import-Module ScheduledTasks -ErrorAction Stop
        $hasScheduledTasks = $true
    } catch {
        $hasScheduledTasks = $false
    }

    if ($hasScheduledTasks) {
        $action  = New-ScheduledTaskAction -Execute "powershell.exe" -Argument ('-ExecutionPolicy Bypass -File "{0}" -UpdateOnly' -f $ScriptFullPath)
        $trigger = New-ScheduledTaskTrigger -Weekly -WeeksInterval 1 -DaysOfWeek $RunDay -At $RunAt

        Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -RunLevel Highest -Force -User "SYSTEM" |
            Out-Null

        Log-Info "Scheduled Task ensured (ScheduledTasks): $TaskName ($RunDay $RunAt)"
    }
    else {
        # schtasks fallback
        $cmd = @(
            "/Create",
            "/F",
            "/RL","HIGHEST",
            "/RU","SYSTEM",
            "/SC","WEEKLY",
            "/D",$RunDay.Substring(0,3).ToUpper(),  # SUN/MON...
            "/ST",$RunAt,
            "/TN",('"{0}"' -f $TaskName),
            "/TR",('"{0}" -ExecutionPolicy Bypass -File "{1}" -UpdateOnly' -f "powershell.exe", $ScriptFullPath)
        ) -join " "

        $out = & schtasks.exe $cmd 2>&1
        Log-Info "Scheduled Task ensured (schtasks): $TaskName ($RunDay $RunAt) output=$out"
    }
}

# ================== MAIN ==================
Ensure-Dir $TaskScriptsDir
Ensure-Dir $TaskLogsDir
"==== $(Get-Date) ====" | Out-File $InfoLog -Append -Encoding UTF8
"==== $(Get-Date) ====" | Out-File $ErrLog  -Append -Encoding UTF8

try {
    Require-FsrmModule

    $patterns = Download-Patterns $PatternsUrl
    Log-Info ("Downloaded patterns: {0}" -f $patterns.Count)

    Ensure-FileGroup $GroupName
    Update-FileGroupPatterns $GroupName $patterns

    if (-not $UpdateOnly) {
        Ensure-FsrmNotifications
        Ensure-Template $TemplateName $GroupName
        Ensure-FileScreens $TargetPaths $TemplateName

        # copy self into TaskScripts for scheduled task stability
        $dest = Join-Path $TaskScriptsDir "FSRM-CryptoWall-AllInOne.ps1"
        Copy-Item -Path $PSCommandPath -Destination $dest -Force
        Log-Info "Copied script to: $dest"

        Ensure-WeeklyTask $dest
        Write-Host "OK: Install complete. Group+Template+Screens+Task ensured."
        Write-Host "Check: Get-FsrmFileGroup; Get-FsrmFileScreenTemplate; Get-FsrmFileScreen"
        Write-Host "Logs: $InfoLog ; $ErrLog"
    } else {
        Write-Host ("OK: UpdateOnly complete. Patterns={0}" -f $patterns.Count)
        Log-Info "UpdateOnly complete"
    }

} catch {
    Log-Err $_
    throw
}
