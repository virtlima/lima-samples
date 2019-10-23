[CmdletBinding()]

$AdminUser = ConvertFrom-Json -InputObject (Get-SECSecretValue -SecretId '{{AdminSecrets}}').SecretString
$SQLUser = ConvertFrom-Json -InputObject (Get-SECSecretValue -SecretId '{{SQLSecrets}}').SecretString
$ClusterAdminUser = '{{DomainNetBIOSName}}' + '\' + $AdminUser.UserName
$SQLAdminUser = '{{DomainNetBIOSName}}' + '\' + $SQLUser.UserName    

if ('{{WSFCFileServerNetBIOSName}}') {
    $ShareName = "\\" + '{{WSFCFileServerNetBIOSName}}' + "." + '{{DomainDnsName}}' + "\witness"
}

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

Configuration WSFCNode1Config {

    $ss = ConvertTo-SecureString -String 'QuickStart' -AsPlaintext -Force
    $Credentials = New-Object PSCredential($AdminSecretARN, $ss)
    $SQLCredentials = New-Object PSCredential($SQLSecretARN, $ss)

    Import-Module -Name PSDscResources
    Import-Module -Name xFailOverCluster
    Import-Module -Name xActiveDirectory
    
    Import-DscResource -Module PSDscResources
    Import-DscResource -ModuleName xFailOverCluster
    Import-DscResource -ModuleName xActiveDirectory
    
    Node 'localhost' {
        WindowsFeature RSAT-AD-PowerShell {
            Name = 'RSAT-AD-PowerShell'
            Ensure = 'Present'
        }

        WindowsFeature AddFailoverFeature {
            Ensure = 'Present'
            Name   = 'Failover-clustering'
            DependsOn = '[WindowsFeature]RSAT-AD-PowerShell' 
        }

        WindowsFeature AddRemoteServerAdministrationToolsClusteringFeature {
            Ensure    = 'Present'
            Name      = 'RSAT-Clustering-Mgmt'
            DependsOn = '[WindowsFeature]AddFailoverFeature'
        }

        WindowsFeature AddRemoteServerAdministrationToolsClusteringPowerShellFeature {
            Ensure    = 'Present'
            Name      = 'RSAT-Clustering-PowerShell'
            DependsOn = '[WindowsFeature]AddRemoteServerAdministrationToolsClusteringFeature'
        }

        WindowsFeature AddRemoteServerAdministrationToolsClusteringCmdInterfaceFeature {
            Ensure    = 'Present'
            Name      = 'RSAT-Clustering-CmdInterface'
            DependsOn = '[WindowsFeature]AddRemoteServerAdministrationToolsClusteringPowerShellFeature'
        }
        
        xADUser SQLServiceAccount {
            DomainName = '{{DomainDnsName}}'
            UserName = $SQLUser.UserName
            Password = $SQLCredentials
            DisplayName = $SQLUser.UserName
            PasswordAuthentication = 'Negotiate'
            DomainAdministratorCredential = $Credentials
            Ensure = 'Present'
            DependsOn = '[WindowsFeature]AddRemoteServerAdministrationToolsClusteringCmdInterfaceFeature' 
        }

        Group Administrators {
            GroupName = 'Administrators'
            Ensure = 'Present'
            MembersToInclude = @($ClusterAdminUser, $SQLAdminUser)
            DependsOn = "[xADUser]SQLServiceAccount"
        }

        xCluster CreateCluster {
            Name                          =  '{{ClusterName}}'
            DomainAdministratorCredential =  $Credentials
            DependsOn                     = '[Group]Administrators'
        }

        if ('{{WSFCFileServerNetBIOSName}}') {
            xClusterQuorum 'SetQuorumToNodeAndFileShareMajority' {
                IsSingleInstance = 'Yes'
                Type             = 'NodeAndFileShareMajority'
                Resource         = $ShareName
                DependsOn        = '[xCluster]CreateCluster'
            }
        } else {
            xClusterQuorum 'SetQuorumToNodeMajority' {
                IsSingleInstance = 'Yes'
                Type             = 'NodeMajority'
                DependsOn        = '[xCluster]CreateCluster'
            }
        }
    }
}
    
WSFCNode1Config -OutputPath 'C:\AWSQuickstart\WSFCNode1Config' -ConfigurationData $ConfigurationData
