
# Getting the DSC Cert Encryption Thumbprint to Secure the MOF File
$DscCertThumbprint = (get-childitem -path cert:\LocalMachine\My | where { $_.subject -eq "CN=AWSQSDscEncryptCert" }).Thumbprint
# Getting Password from Secrets Manager for AD Admin User
$AdminUser = ConvertFrom-Json -InputObject (Get-SECSecretValue -SecretId $AdminSecret).SecretString
$SQLUser = ConvertFrom-Json -InputObject (Get-SECSecretValue -SecretId $SQLSecret).SecretString
$ClusterAdminUser = $DomainNetBIOSName + '\' + $AdminUser.UserName
$SQLAdminUser = $DomainNetBIOSName + '\' + $SQLUser.UserName
# Creating Credential Object for Administrator
$Credentials = (New-Object PSCredential($ClusterAdminUser,(ConvertTo-SecureString $AdminUser.Password -AsPlainText -Force)))
$SQLCredentials = (New-Object PSCredential($SQLAdminUser,(ConvertTo-SecureString $SQLUser.Password -AsPlainText -Force)))
# Getting the Name Tag of the Instance
$NameTag = (Get-EC2Tag -Filter @{ Name="resource-id";Values=(Invoke-RestMethod -Method Get -Uri http://169.254.169.254/latest/meta-data/instance-id)}| Where-Object { $_.Key -eq "Name" })
$NetBIOSName = $NameTag.Value

$IPADDR = 'IP/CIDR' -replace 'IP',$AGListener1PrivateIP1 -replace 'CIDR',(Convert-CidrtoSubnetMask -SubnetMaskCidr (Get-CIDR -Target $WSFCNode1NetBIOSName))
$IPADDR2 = 'IP/CIDR' -replace 'IP',$AGListener1PrivateIP2 -replace 'CIDR',(Convert-CidrtoSubnetMask -SubnetMaskCidr (Get-CIDR -Target $WSFCNode2NetBIOSName))
if ($AGListener1PrivateIP3) {
    $IPADDR3 = 'IP/CIDR' -replace 'IP',$AGListener1PrivateIP3 -replace 'CIDR',(Convert-CidrtoSubnetMask -SubnetMaskCidr (Get-CIDR -Target $WSFCNode3NetBIOSName))  
}

if ($ManagedAD -eq 'Yes'){
    $DN = Get-Domain
    $IdentityReference = $DomainNetBIOSName + "\" + $ClusterName + "$"
    $OUPath = 'OU=Computers,OU=' + $DomainNetBIOSName + "," + $DN
}



$ConfigurationData = @{
    AllNodes = @(
        @{
            NodeName     = '*'
            CertificateFile = "C:\AWSQuickstart\publickeys\AWSQSDscPublicKey.cer"
            Thumbprint = $DscCertThumbprint
            PSDscAllowDomainUser = $true
        },
        @{
            NodeName = $NetBIOSName
        }
    )
}

Configuration AddAG {
    param(
        [Parameter(Mandatory = $true)]
        [PSCredential]$SQLCredentials,

        [Parameter(Mandatory = $true)]
        [PSCredential]$Credentials
    )

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
            ServerName              = $NetBIOSName
            InstanceName            = 'MSSQLSERVER'
            PsDscRunAsCredential    = $SQLCredentials
            ProcessOnlyOnActiveNode = $true
        }

        SqlServerConfiguration 'SQLConfigPriorityBoost'{
            ServerName     = $NetBIOSName
            InstanceName   = 'MSSQLSERVER'
            OptionName     = 'cost threshold for parallelism'
            OptionValue    = 20
        }

        SqlAlwaysOnService 'EnableAlwaysOn' {
            Ensure               = 'Present'
            ServerName           = $NetBIOSName
            InstanceName         = 'MSSQLSERVER'
            PsDscRunAsCredential = $SQLCredentials
        }

        SqlServerLogin 'AddNTServiceClusSvc' {
            Ensure               = 'Present'
            Name                 = 'NT SERVICE\ClusSvc'
            LoginType            = 'WindowsUser'
            ServerName           = $NetBIOSName
            InstanceName         = 'MSSQLSERVER'
            PsDscRunAsCredential = $SQLCredentials
        }

        SqlServerPermission 'AddNTServiceClusSvcPermissions' {
            DependsOn            = '[SqlServerLogin]AddNTServiceClusSvc'
            Ensure               = 'Present'
            ServerName           = $NetBIOSName
            InstanceName         = 'MSSQLSERVER'
            Principal            = 'NT SERVICE\ClusSvc'
            Permission           = 'AlterAnyAvailabilityGroup', 'ViewServerState'
            PsDscRunAsCredential = $SQLCredentials
        }

        SqlServerEndpoint 'HADREndpoint' {
            EndPointName         = 'HADR'
            Ensure               = 'Present'
            Port                 = 5022
            ServerName           = $NetBIOSName
            InstanceName         = 'MSSQLSERVER'
            PsDscRunAsCredential = $SQLCredentials
        }
        
        if ($ManagedAD -eq 'Yes'){
            WindowsFeature RSAT-ADDS-Tools {
                Name = 'RSAT-ADDS-Tools'
                Ensure = 'Present'
            }

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
            Name                 = $AvailabiltyGroupName
            InstanceName         = 'MSSQLSERVER'
            ServerName           = $NetBIOSName
            AvailabilityMode     = 'SynchronousCommit'
            FailoverMode         = 'Automatic'
            DependsOn = '[SqlAlwaysOnService]EnableAlwaysOn', '[SqlServerEndpoint]HADREndpoint', '[SqlServerPermission]AddNTServiceClusSvcPermissions'
            PsDscRunAsCredential = $SQLCredentials
        }

        if ($AGListener1PrivateIP3) {
            SqlAGListener 'AGListener1' {
                Ensure               = 'Present'
                ServerName           = $NetBIOSName
                InstanceName         = 'MSSQLSERVER'
                AvailabilityGroup    = $AvailabiltyGroupName
                Name                 = $AvailabiltyGroupName
                IpAddress            = $IPADDR,$IPADDR2,$IPADDR3
                Port                 = 5301
                DependsOn            = '[SqlAG]AddSQLAG1'
                PsDscRunAsCredential = $SQLCredentials
            }
        } else {
            SqlAGListener 'AGListener1' {
                Ensure               = 'Present'
                ServerName           = $NetBIOSName
                InstanceName         = 'MSSQLSERVER'
                AvailabilityGroup    = $AvailabiltyGroupName
                Name                 = $AvailabiltyGroupName
                IpAddress            = $IPADDR,$IPADDR2
                Port                 = 5301
                DependsOn            = '[SqlAG]AddSQLAG1'
                PsDscRunAsCredential = $SQLCredentials
            }
        }
    }
}

AddAG -OutputPath 'C:\AWSQuickstart\AddAG' -Credentials $Credentials -SQLCredentials $SQLCredentials -ConfigurationData $ConfigurationData