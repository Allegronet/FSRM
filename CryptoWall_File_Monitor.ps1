#requires -version 2
<#

.NOTES
  Version:        3.0
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


New-FsrmFileGroup -Name "CryptoWall File Monitor" -IncludePattern @((Invoke-WebRequest -Uri "https://raw.githubusercontent.com/Allegronet/FSRM/refs/heads/main/fsrm-block-lost.txt" -UseBasicParsing).content | convertfrom-json | % {$_.filters})

Set-FsrmSetting -SmtpServer "smtp.allegronet.co.il" -AdminEmailAddress "noc@allegronet.co.il"
$Notification = New-FsrmAction -Type Email -MailTo "[Admin Email]" -Subject "Unauthorized file matching [Violated File Group] file group detected" -Body "The system detected that user [Source Io Owner] attempted to save [Source File Path] on [File Screen Path] on server [Server]. This file matches the [Violated File Group] file group which is not permitted on the system." -RunLimitInterval 120
$EventLog = New-FsrmAction Event -EventType Information -Body "The system detected that user [Source Io Owner] attempted to save [Source File Path] on [File Screen Path] on server [Server]. This file matches the [Violated File Group] file group which is not permitted on the system." -RunLimitInterval 180
New-FsrmFileScreenTemplate -Name "CryptoWall File Monitor" -IncludeGroup "CryptoWall File Monitor" -Notification ($Notification, $EventLog) -Active


#----------------------------------------------------------[weekly update]--------------------------------------------------------------------------------------------------

$action = New-ScheduledTaskAction -Execute 'Powershell.exe' -Argument '-NoProfile -WindowStyle Hidden -command "& {set-FsrmFileGroup -name ''CryptoWall File Monitor'' -IncludePattern @((Invoke-WebRequest -Uri "https://raw.githubusercontent.com/Allegronet/FSRM/refs/heads/main/fsrm-block-lost.txt" -UseBasicParsing).content | % {$_.filters})}"'

$trigger =  New-ScheduledTaskTrigger -Weekly -WeeksInterval 1 -DaysOfWeek Sunday -At 9am

$task = New-ScheduledTask -Action $action  -Description "FSRM weekly update Crypto extensions" -Trigger $trigger

Register-ScheduledTask -Action $action -TaskName "FSRM weekly update Crypto extensions" -RunLevel Highest -Force -User "System" -Trigger $trigger

