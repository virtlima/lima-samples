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

Configuration AddAG {
    $ss = ConvertTo-SecureString -String 'QuickStart' -AsPlaintext -Force
    $Credentials = New-Object PSCredential('{ssm:AdminSecretARN}', $ss)
    $SQLCredentials = New-Object PSCredential('{ssm:SQLSecretARN}', $ss)

    Import-Module -Name PSDesiredStateConfiguration
    Import-Module -Name xActiveDirectory
    Import-Module -Name SqlServerDsc
    
    Import-DscResource -Module PSDesiredStateConfiguration
    Import-DscResource -Module xActiveDirectory
    Import-DscResource -Module SqlServerDsc

    Node 'localhost' {
        SqlServerMaxDop 'SQLServerMaxDopAuto' {
            Ensure                  = 'Present'
            DynamicAlloc            = $true
            ServerName              = '{tag:Name}'
            InstanceName            = 'MSSQLSERVER'
            PsDscRunAsCredential    = $SQLCredentials
            ProcessOnlyOnActiveNode = $true
        }

        SqlServerConfiguration 'SQLConfigPriorityBoost'{
            ServerName     = '{tag:Name}'
            InstanceName   = 'MSSQLSERVER'
            OptionName     = 'cost threshold for parallelism'
            OptionValue    = 20
        }

        SqlAlwaysOnService 'EnableAlwaysOn' {
            Ensure               = 'Present'
            ServerName           = '{tag:Name}'
            InstanceName         = 'MSSQLSERVER'
            PsDscRunAsCredential = $SQLCredentials
        }

        SqlServerLogin 'AddNTServiceClusSvc' {
            Ensure               = 'Present'
            Name                 = 'NT SERVICE\ClusSvc'
            LoginType            = 'WindowsUser'
            ServerName           = '{tag:Name}'
            InstanceName         = 'MSSQLSERVER'
            PsDscRunAsCredential = $SQLCredentials
        }

        SqlServerPermission 'AddNTServiceClusSvcPermissions' {
            DependsOn            = '[SqlServerLogin]AddNTServiceClusSvc'
            Ensure               = 'Present'
            ServerName           = '{tag:Name}'
            InstanceName         = 'MSSQLSERVER'
            Principal            = 'NT SERVICE\ClusSvc'
            Permission           = 'AlterAnyAvailabilityGroup', 'ViewServerState'
            PsDscRunAsCredential = $SQLCredentials
        }

        SqlServerEndpoint 'HADREndpoint' {
            EndPointName         = 'HADR'
            Ensure               = 'Present'
            Port                 = 5022
            ServerName           = '{tag:Name}'
            InstanceName         = 'MSSQLSERVER'
            PsDscRunAsCredential = $SQLCredentials
        }

        SqlAGReplica 'AddReplica' {
            Ensure                     = 'Present'
            Name                       = '{tag:Name}'
            AvailabilityGroupName      = '{{AvailabiltyGroupName}}'
            ServerName                 = '{tag:Name}'
            InstanceName               = 'MSSQLSERVER'
            PrimaryReplicaServerName   = '{{WSFCNode1NetBIOSName}}'
            PrimaryReplicaInstanceName = 'MSSQLSERVER'
            AvailabilityMode           = 'SynchronousCommit'
            FailoverMode               = 'Automatic'
            DependsOn                  = '[SqlAlwaysOnService]EnableAlwaysOn' 
            ProcessOnlyOnActiveNode    = $true
            PsDscRunAsCredential       = $SQLCredentials
        }
    }
}

AddAG -OutputPath 'C:\AWSQuickstart\AddAG' -ConfigurationData $ConfigurationData