#Requires -Modules @{ModuleName='AWS.Tools.Common';ModuleVersion='4.1.0.0'}
#Requires -Modules @{ModuleName='AWS.Tools.EC2';ModuleVersion='4.1.0.0'}
#Requires -Modules @{ModuleName='AWS.Tools.AutoScaling';ModuleVersion='4.1.0.0'}
#Requires -Modules @{ModuleName='AWS.Tools.SimpleSystemsManagement';ModuleVersion='4.1.0.0'}

$split = $LambdaInput -split ","
$instanceId = $split[0]
$asgLifeCycleTransition = $split[1]
$region = $split[2]
Write-Host $LambdaInput

Set-DefaultAWSRegion -Region $region
#if ($asgLifeCycleTransition -eq "autoscaling:EC2_INSTANCE_LAUNCHING") {
#    Send-SSMCommand -DocumentName "AWS-RunRemoteScript" -InstanceIds $instanceId -Parameter @{sourceType='S3';sourceInfo='{"path": "https://syahmad-cmh.s3.us-east-2.amazonaws.com/PowerShell/Scripts/JoinInstanceToDomain.ps1"}';commandLine=".\JoinInstanceToDomain.ps1"} -Verbose
#}
#
#if ($asgLifeCycleTransition -eq "autoscaling:EC2_INSTANCE_TERMINATING") {
#    Send-SSMCommand -DocumentName "AWS-RunRemoteScript" -InstanceIds $instanceId -Parameter @{sourceType='S3';sourceInfo='{"path": "https://syahmad-cmh.s3.us-east-2.amazonaws.com/PowerShell/Scripts/UnjoinFromDomain.ps1"}';commandLine=".\UnjoinFromDomain.ps1"} -Verbose
#}
Clear-DefaultAWSRegion