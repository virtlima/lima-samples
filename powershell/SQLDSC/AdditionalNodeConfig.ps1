
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
    $Credentials = New-Object PSCredential('{ssm:AdminSecretARN}', $ss)

    Import-Module -Name xFailOverCluster
    Import-Module -Name PSDscResources
    
    Import-DscResource -ModuleName xFailOverCluster
    Import-DscResource -ModuleName PSDscResources

    Node 'localhost'{

        Group Administrators {
            GroupName = 'Administrators'
            Ensure = 'Present'
            MembersToInclude = @('{{DomainNetBIOSName}}\{{GetAdminUser.Name}}', '{{DomainNetBIOSName}}\{{GetSQLUser.Name}}')
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
            Name             = '{{ClusterName}}'
            RetryIntervalSec = 10
            RetryCount       = 60
            DependsOn        = '[WindowsFeature]AddRemoteServerAdministrationToolsClusteringCmdInterfaceFeature'
        }

        xCluster JoinNodeToCluster {
            Name                          = '{{ClusterName}}'
            StaticIPAddress               = '{{WSFCNodePrivateIP2}}'
            DomainAdministratorCredential = $Credentials
            DependsOn                     = '[xWaitForCluster]WaitForCluster'
        }
    }
}

AdditionalWSFCNode -OutputPath 'C:\AWSQuickstart\AdditionalWSFCNode' -ConfigurationData $ConfigurationData