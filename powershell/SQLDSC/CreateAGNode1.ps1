[CmdletBinding()]
param(

    [Parameter(Mandatory=$true)]
    [string]$DomainNetBIOSName,

    [Parameter(Mandatory=$true)]
    [string]$DomainDNSName,

    [Parameter(Mandatory=$true)]
    [string]$AdminSecret,

    [Parameter(Mandatory=$true)]
    [string]$SQLSecret,

    [Parameter(Mandatory=$true)]
    [string]$ClusterName,

    [Parameter(Mandatory=$true)]
    [string]$AvailabiltyGroupName,

    [Parameter(Mandatory=$true)]
    [string]$WSFCNode1NetBIOSName,

    [Parameter(Mandatory=$true)]
    [string]$WSFCNode2NetBIOSName,

    [Parameter(Mandatory=$true)]
    [string]$AGListener1PrivateIP1,

    [Parameter(Mandatory=$true)]
    [string]$AGListener1PrivateIP2,

    [Parameter(Mandatory=$false)]
    [string]$WSFCNode3NetBIOSName,

    [Parameter(Mandatory=$false)]
    [string]$AGListener1PrivateIP3,

    [Parameter(Mandatory=$false)]
    [string] $ManagedAD

)

# Getting the Name Tag of the Instance
$NameTag = (Get-EC2Tag -Filter @{ Name="resource-id";Values=(Invoke-RestMethod -Method Get -Uri http://169.254.169.254/latest/meta-data/instance-id)}| Where-Object { $_.Key -eq "Name" })
$NetBIOSName = $NameTag.Value

$ConfigurationData = @{
    AllNodes = @(
        @{
            NodeName="*"
            PSDscAllowPlainTextPassword = $true
            PSDscAllowDomainUser = $true
        },
        @{
            NodeName = $NetBIOSName
        }
    )
}

Configuration AddAG {
    $ss = ConvertTo-SecureString -String 'QuickStart' -AsPlaintext -Force
    $Credentials = New-Object PSCredential('{ssm:AdminSecretARN}', $ss)
    $SQLCredentials = New-Object PSCredential('{ssm:SQLSecretARN}', $ss)

    $IPADDR = 'IP/CIDR' -replace 'IP',$AGListener1PrivateIP1 -replace 'CIDR',(Convert-CidrtoSubnetMask -SubnetMaskCidr (Get-CIDR -Target $WSFCNode1NetBIOSName))
    $IPADDR2 = 'IP/CIDR' -replace 'IP',$AGListener1PrivateIP2 -replace 'CIDR',(Convert-CidrtoSubnetMask -SubnetMaskCidr (Get-CIDR -Target $WSFCNode2NetBIOSName))
    if ('{$AGListener1PrivateIP3}') {
        $IPADDR3 = 'IP/CIDR' -replace 'IP',$AGListener1PrivateIP3 -replace 'CIDR',(Convert-CidrtoSubnetMask -SubnetMaskCidr (Get-CIDR -Target $WSFCNode3NetBIOSName))  
    }

    Import-Module -Name PSDesiredStateConfiguration
    Import-Module -Name xActiveDirectory
    Import-Module -Name SqlServerDsc
    
    Import-DscResource -Module PSDesiredStateConfiguration
    Import-DscResource -Module xActiveDirectory
    Import-DscResource -Module SqlServerDsc

    Node $AllNodes.NodeName {
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
        
        if ('{{ManagedAD}}' -eq 'Yes'){
            WindowsFeature RSAT-ADDS-Tools {
                Name = 'RSAT-ADDS-Tools'
                Ensure = 'Present'
            }

            $DN = get-addomain '{{DomainDNSName}}' | Select-Object distinguishedname
            $IdentityReference = '{{DomainNetBIOSName}}' + "\" + $ClusterName + "$"
            $OUPath = 'OU=Computers,OU=' + '{{DomainNetBIOSName}}' + "," + $DN

            xADObjectPermissionEntry 'ADObjectPermissionEntry' {
                Ensure                             = 'Present'
                Path                               = $OUPath
                IdentityReference                  = $IdentityReference
                ActiveDirectoryRights              = 'GenericAll'
                AccessControlType                  = 'Allow'
                ObjectType                         = '00000000-0000-0000-0000-000000000000'
                ActiveDirectorySecurityInheritance = 'All'
                InheritedObjectType                = '00000000-0000-0000-0000-000000000000'
                PsDscRunAsCredential               = $Credentials
            }
        }

        SqlAG 'AddSQLAG1' {
            Ensure               = 'Present'
            Name                 = '{(AvailabiltyGroupName}}'
            InstanceName         = 'MSSQLSERVER'
            ServerName           = '{tag:Name}'
            AvailabilityMode     = 'SynchronousCommit'
            FailoverMode         = 'Automatic'
            DependsOn = '[SqlAlwaysOnService]EnableAlwaysOn', '[SqlServerEndpoint]HADREndpoint', '[SqlServerPermission]AddNTServiceClusSvcPermissions'
            PsDscRunAsCredential = $SQLCredentials
        }

        if ($AGListener1PrivateIP3) {
            SqlAGListener 'AGListener1' {
                Ensure               = 'Present'
                ServerName           = '{tag:Name}'
                InstanceName         = 'MSSQLSERVER'
                AvailabilityGroup    = '{(AvailabiltyGroupName}}'
                Name                 = '{(AvailabiltyGroupName}}'
                IpAddress            = $IPADDR,$IPADDR2,$IPADDR3
                Port                 = 5301
                DependsOn            = '[SqlAG]AddSQLAG1'
                PsDscRunAsCredential = $SQLCredentials
            }
        } else {
            SqlAGListener 'AGListener1' {
                Ensure               = 'Present'
                ServerName           = '{tag:Name}'
                InstanceName         = 'MSSQLSERVER'
                AvailabilityGroup    = '{(AvailabiltyGroupName}}'
                Name                 = '{(AvailabiltyGroupName}}'
                IpAddress            = $IPADDR,$IPADDR2
                Port                 = 5301
                DependsOn            = '[SqlAG]AddSQLAG1'
                PsDscRunAsCredential = $SQLCredentials
            }
        }
    }
}

AddAG -OutputPath 'C:\AWSQuickstart\AddAG' -Credentials $Credentials -SQLCredentials $SQLCredentials -ConfigurationData $ConfigurationData