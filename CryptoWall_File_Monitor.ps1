#requires -version 2
<#

.NOTES
  Version:        4.0
  Author:         edk
  Creation Date:  22/12/2024
  Purpose/Change:   auto update Crypto extensions from: "https://raw.githubusercontent.com/Allegronet/FSRM/refs/heads/main/fsrm-block-lost.txt" on running
                    auto weekly update Crypto extensions from:"https://raw.githubusercontent.com/Allegronet/FSRM/refs/heads/main/fsrm-block-lost.txt"
  
  ***before use do this:

  ***Locate the following registry entry: HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Services\srmsvc

  ***From the right-side pane, right-click DependOnService, and then click Modify.

  ***Add WINMGMT to the Multi-String Value.

  ***Click OK and then exit the registry editor.

  ***Reboot the computer


.to do

#>

#---------------------------------------------------------[Initialisations]--------------------------------------------------------


$fsrmGroupName = "CryptoWall File Monitor"
$patternFileUrl = "https://raw.githubusercontent.com/Allegronet/FSRM/main/fsrm-block-lost.txt"
$noc_mail = "noc@allegronet.co.il"

 $response = Invoke-WebRequest -Uri $patternFileUrl -UseBasicParsing

 #$patterns = $response.Content -split "`r?`n" | Where-Object { $_ -ne "" }

New-FsrmFileGroup -Name $fsrmGroupName -IncludePattern $response.Content


Set-FsrmSetting -SmtpServer "smtp.allegronet.co.il" -AdminEmailAddress $noc_mail
$Notification = New-FsrmAction -Type Email -MailTo "[Admin Email]" -Subject "Unauthorized file matching [Violated File Group] file group detected" -Body "The system detected that user [Source Io Owner] attempted to save [Source File Path] on [File Screen Path] on server [Server]. This file matches the [Violated File Group] file group which is not permitted on the system." -RunLimitInterval 120
$EventLog = New-FsrmAction Event -EventType Information -Body "The system detected that user [Source Io Owner] attempted to save [Source File Path] on [File Screen Path] on server [Server]. This file matches the [Violated File Group] file group which is not permitted on the system." -RunLimitInterval 180
New-FsrmFileScreenTemplate -Name "CryptoWall File Monitor" -IncludeGroup "CryptoWall File Monitor" -Notification ($Notification, $EventLog) -Active




#-----------------------------------------fsrmUpdate.ps1-----------------------------------------------
try {

mkdir C:\TaskScripts
C:\TaskLogs

}
catch{}

$git = "https://raw.githubusercontent.com/Allegronet/FSRM/refs/heads/main/fsrmUpdate.ps1"

try {
        (Invoke-WebRequest -Uri $git -UseBasicParsing).Content | Out-File -FilePath C:\TaskScripts\FSRMUpdate.ps1
    
} catch {
    Write-Output $_ | Out-File -FilePath "C:\TaskLogs\FSRM-Error.log"
}


#----------------------------------------------------------[weekly update]--------------------------------------------------------------------------------------------------

$action = New-ScheduledTaskAction -Execute 'Powershell.exe' -Argument '-file "C:\TaskScripts\FSRMUpdate.ps1"'

$trigger =  New-ScheduledTaskTrigger -Weekly -WeeksInterval 1 -DaysOfWeek Sunday -At 9am

$task = New-ScheduledTask -Action $action  -Description "weekly update FSRM Crypto extensions" -Trigger $trigger

Register-ScheduledTask -Action $action -TaskName "FSRM weekly update Crypto extensions" -RunLevel Highest -Force -User "System" -Trigger $trigger



