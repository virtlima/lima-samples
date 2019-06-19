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

Configuration AdditionalWSFCNode {

    $ss = ConvertTo-SecureString -String 'QuickStart' -AsPlaintext -Force
    $Credentials = New-Object PSCredential('/quickstart/secrets/SIOS/DKCE/DomainAdminUser', $ss)
    $SQLCredentials = New-Object PSCredential('/quickstart/secrets/SIOS/DKCE/SQLServiceAccount', $ss)

    Import-Module -Name xFailOverCluster
    Import-Module -Name PSDscResources
    
    Import-DscResource -ModuleName xFailOverCluster
    Import-DscResource -ModuleName PSDscResources

    Node 'localhost'{

        if ('{ssm:/quickstart/SIOS/DKCE/ShareName}' -eq 'None' ){
            Group Administrators {
                GroupName = 'Administrators'
                Ensure = 'Present'
                MembersToInclude = @('{ssm:/quickstart/SIOS/DKCE/DomainAdminUser}')
            }
        } else {
            Group Administrators {
                GroupName = 'Administrators'
                Ensure = 'Present'
                MembersToInclude = @('{ssm:/quickstart/SIOS/DKCE/DomainAdminUser}','{ssm:/quickstart/SIOS/DKCE/SQLServiceAccount}')
            }
        }

        WindowsFeature AddFailoverFeature {
            Ensure = 'Present'
            Name   = 'Failover-clustering'
            DependsOn = '[Group]Administrators'
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

        xWaitForCluster WaitForCluster {
            Name             = '{ssm:/quickstart/SIOS/DKCE/ClusterName}'
            RetryIntervalSec = 10
            RetryCount       = 60
            DependsOn        = '[WindowsFeature]AddRemoteServerAdministrationToolsClusteringCmdInterfaceFeature'
        }

        xCluster JoinNodeToCluster {
            Name                          = '{ssm:/quickstart/SIOS/DKCE/ClusterName}'
            StaticIPAddress               = '{ssm:/quickstart/SIOS/DKCE/WSFCNode2PrivateIP2}'
            DomainAdministratorCredential = $Credentials
            DependsOn                     = '[xWaitForCluster]WaitForCluster'
        }
    }
}

AdditionalWSFCNode -OutputPath 'C:\AWSQuickstart\AdditionalWSFCNode' -ConfigurationData $ConfigurationData