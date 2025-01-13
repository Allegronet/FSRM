[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
try {
    Set-FsrmFileGroup -Name "CryptoWall File Monitor" -IncludePattern (
        (Invoke-WebRequest -Uri "https://raw.githubusercontent.com/Allegronet/FSRM/refs/heads/main/fsrm-block-lost.txt" -UseBasicParsing).Content -split "`r?`n" |
        Where-Object { $_ -ne "" }
    )
} catch {
    Write-Output $_ | Out-File -FilePath "C:\TaskLogs\FSRM-Error.log"
}
