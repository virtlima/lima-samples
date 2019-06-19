[CmdletBinding()]
param(

    [Parameter(Mandatory=$true)]
    [string]$Secret

)

Write-Host $Secret