[CmdletBinding()]
param()

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
    $Credentials = New-Object PSCredential('/quickstart/secrets/SIOS/DKCE/DomainAdminUser', $ss)
    $SQLCredentials = New-Object PSCredential('/quickstart/secrets/SIOS/DKCE/SQLServiceAccount', $ss)

    Import-Module -Name PSDscResources
    Import-Module -Name xFailOverCluster
    Import-Module -Name xActiveDirectory
    
    Import-DscResource -Module PSDscResources
    Import-DscResource -ModuleName xFailOverCluster
    Import-DscResource -ModuleName xActiveDirectory
    
    Node 'localhost' {

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
        
        WindowsFeature RSAT-AD-PowerShell {
            Name = 'RSAT-AD-PowerShell'
            Ensure = 'Present'
        }

        if ('{ssm:/quickstart/SIOS/DKCE/ShareName}' -eq 'None' ) {
            Group Administrators {
                GroupName = 'Administrators'
                Ensure = 'Present'
                MembersToInclude = @('{ssm:/quickstart/SIOS/DKCE/DomainAdminUser}')
                DependsOn = "[xADUser]SQLServiceAccount"
            }
        } else {
            xADUser SQLServiceAccount {
                DomainName = '{ssm:/quickstart/SIOS/DKCE/DomainName}'
                UserName = '{ssm:/quickstart/SIOS/DKCE/SQLServiceAccount}'
                Password = $SQLCredentials
                DisplayName = 'SQL Service Account'
                PasswordAuthentication = 'Negotiate'
                DomainAdministratorCredential = $Credentials
                Ensure = 'Present'
                DependsOn = '[WindowsFeature]AddRemoteServerAdministrationToolsClusteringCmdInterfaceFeature' 
            }

            Group Administrators {
                GroupName = 'Administrators'
                Ensure = 'Present'
                MembersToInclude = @('{ssm:/quickstart/SIOS/DKCE/DomainAdminUser}','{ssm:/quickstart/SIOS/DKCE/SQLServiceAccount}')
                DependsOn = "[xADUser]SQLServiceAccount"
            }
        }

        xCluster CreateCluster {
            Name                          =  '{ssm:/quickstart/SIOS/DKCE/ClusterName}'
            StaticIPAddress               =  '{ssm:/quickstart/SIOS/DKCE/WSFCNode1PrivateIP2}'
            DomainAdministratorCredential =  $Credentials
            DependsOn                     = '[Group]Administrators'
        }
        
        xClusterQuorum 'SetQuorumToNodeAndFileShareMajority' {
            IsSingleInstance = 'Yes'
            Type             = 'NodeAndFileShareMajority'
            Resource         = '{ssm:/quickstart/SIOS/DKCE/ShareName}'
            DependsOn        = '[xCluster]CreateCluster'
        }
    }
}

WSFCNode1Config -OutputPath 'C:\AWSQuickstart\WSFCNode1Config' -ConfigurationData $ConfigurationData
