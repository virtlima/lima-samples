[CmdletBinding()]
# Incoming Parameters for Script, CloudFormation\SSM Parameters being passed in
param()

# Creating Configuration Data Block that has the Certificate Information for DSC Configuration Processing
$ConfigurationData = @{
    AllNodes = @(
        @{
            NodeName="*"
            PSDscAllowPlainTextPassword = $true
            PSDscAllowDomainUser = $true
        },
        @{
            NodeName = 'localhost'
        }
    )
}

Configuration DomainJoin {

    $ss = ConvertTo-SecureString -String 'QuickStart' -AsPlaintext -Force
    $Credentials = New-Object PSCredential('/quickstart/secrets/SIOS/DKCE/DomainAdminUser', $ss)

    Import-Module -Name PSDesiredStateConfiguration
    Import-Module -Name ComputerManagementDsc
    
    Import-DscResource -Module PSDesiredStateConfiguration
    Import-DscResource -Module ComputerManagementDsc

    Node 'localhost' {

        Computer JoinDomain {
            Name = '{tag:ComputerName}'
            DomainName = '{ssm:/quickstart/SIOS/DKCE/DomainName}'
            Credential = $Credentials
        }
    }
}

DomainJoin -OutputPath 'C:\AWSQuickstart\DomainJoin' -ConfigurationData $ConfigurationData