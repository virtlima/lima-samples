[CmdletBinding()]
param(

    [Parameter(Mandatory=$true)]
    [string]$Account

)

$Arn = 'arn:aws:iam::' + $Account + ':role/OrganizationAccountAccessRole'
Write-Host $Arn

$Creds = (Use-STSRole -RoleArn "$Arn" -RoleSessionName "MyRoleSessionName").Credentials

get-iamroles -Credential $Creds