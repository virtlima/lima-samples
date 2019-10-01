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
    $Credentials = New-Object PSCredential('{ssm:AdminSecretARN}', $ss)

    Import-Module -Name PSDesiredStateConfiguration
    Import-Module -Name ComputerManagementDsc
    
    Import-DscResource -Module PSDesiredStateConfiguration
    Import-DscResource -Module ComputerManagementDsc

    Node 'localhost' {

        Computer JoinDomain {
            Name = '{tag:Name}'
            DomainName = '{{DomainDNSName}}'
            Credential = $Credentials
        }
    }
}

DomainJoin -OutputPath 'C:\AWSQuickstart\DomainJoin' -ConfigurationData $ConfigurationData