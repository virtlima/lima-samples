[CmdletBinding()]
# Incoming Parameters for Script, CloudFormation\SSM Parameters being passed in
param()

# Creating Configuration Data Block that allows plain test password 
# for DSC Configuration Processing
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
    $Credentials = New-Object PSCredential('{ssm:/demo/AD/AdminSecretARN}', $ss)

    Import-Module -Name PSDesiredStateConfiguration
    Import-Module -Name ComputerManagementDsc
    
    Import-DscResource -Module PSDesiredStateConfiguration
    Import-DscResource -Module ComputerManagementDsc

    Node 'localhost' {

        Computer JoinDomain {
            Name = '{tag:Name}'
            DomainName = '{ssm:/demo/AD/DomainName}'
            Credential = $Credentials
        }
    }
}

DomainJoin -OutputPath 'C:\MofFiles\DomainJoin' -ConfigurationData $ConfigurationData