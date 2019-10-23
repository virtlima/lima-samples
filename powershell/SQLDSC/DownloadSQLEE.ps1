[CmdletBinding()]

param(

    [Parameter(Mandatory=$true)]
    [string]
    $SQLServerVersion

)

try {
    Start-Transcript -Path C:\AWSQuickstart\log\DownloadSQLEE.ps1.txt -Append

    $ErrorActionPreference = "Stop"

    $DestPath = "C:\SQLMedia"
    New-Item "$DestPath" -Type directory -Force

    $ssmssource = "https://download.microsoft.com/download/3/C/7/3C77BAD3-4E0F-4C6B-84DD-42796815AFF6/SSMS-Setup-ENU.exe"

    if ($SQLServerVersion -eq "2016") {
        $source = "https://download.microsoft.com/download/9/0/7/907AD35F-9F9C-43A5-9789-52470555DB90/ENU/SQLServer2016SP1-FullSlipstream-x64-ENU.iso"
    }
    else {
        $source = "https://download.microsoft.com/download/E/F/2/EF23C21D-7860-4F05-88CE-39AA114B014B/SQLServer2017-x64-ENU.iso"
    }

    $tries = 5
    while ($tries -ge 1) {
        try {
            Start-BitsTransfer -Source $source -Destination "$DestPath" -ErrorAction Stop
            Start-BitsTransfer -Source $ssmssource -Destination "$DestPath" -ErrorAction Stop
            break
        } 
        catch {
            $tries--
            Write-Verbose "Exception:"
            Write-Verbose "$_"
            if ($tries -lt 1) {
                throw $_
            }
            else {
                Write-Verbose "Failed download. Retrying again in 5 seconds"
                Start-Sleep 5
            }
        }
    }
}
catch {
    Write-Verbose "$($_.exception.message)@ $(Get-Date)"
}
