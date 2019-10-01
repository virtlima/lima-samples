[CmdletBinding()]
param(

    [Parameter(Mandatory=$true)]
    [string]$DomainNetBIOSName,

    [Parameter(Mandatory=$true)]
    [string]$AdminSecret,

    [Parameter(Mandatory=$true)]
    [string]$SQLSecret

)

# Getting the DSC Cert Encryption Thumbprint to Secure the MOF File
$DscCertThumbprint = (get-childitem -path cert:\LocalMachine\My | where { $_.subject -eq "CN=AWSQSDscEncryptCert" }).Thumbprint
# Getting Password from Secrets Manager for AD Admin User
$AdminUser = ConvertFrom-Json -InputObject (Get-SECSecretValue -SecretId $AdminSecret).SecretString
$SQLUser = ConvertFrom-Json -InputObject (Get-SECSecretValue -SecretId $SQLSecret).SecretString
$DomainAdminUser = $DomainNetBIOSName + '\' + $AdminUser.username
$SQLAdminUser = $DomainNetBIOSName + '\' + $SQLUser.username
# Creating Credential Object for Administrator
$Credentials = (New-Object PSCredential($DomainAdminUser,(ConvertTo-SecureString $AdminUser.password -AsPlainText -Force)))
$SQLCredentials = (New-Object PSCredential($SQLAdminUser,(ConvertTo-SecureString $SQLUser.password -AsPlainText -Force)))
# Getting the Name Tag of the Instance
$NameTag = (Get-EC2Tag -Filter @{ Name="resource-id";Values=(Invoke-RestMethod -Method Get -Uri http://169.254.169.254/latest/meta-data/instance-id)}| Where-Object { $_.Key -eq "Name" })
$NetBIOSName = $NameTag.Value

$ConfigurationData = @{
    AllNodes = @(
        @{
            NodeName     = '*'
            CertificateFile = "C:\AWSQuickstart\publickeys\AWSQSDscPublicKey.cer"
            Thumbprint = $DscCertThumbprint
            PSDscAllowDomainUser = $true
        },
        @{
            NodeName = 'localhost'
        }
    )
}

Configuration ReconfigureSQL {
    
    param(
        [Parameter(Mandatory = $true)]
        [PSCredential]$SQLCredentials,

        [Parameter(Mandatory = $true)]
        [PSCredential]$Credentials
    )

    Import-Module -Name PSDesiredStateConfiguration
    Import-Module -Name SqlServerDsc
    Import-Module SQLPS

    Import-DscResource -Module PSDesiredStateConfiguration
    Import-DscResource -Module SqlServerDsc

    Node $AllNodes.NodeName {
        SqlServerLogin 'AddSQLAdmin' {
            Ensure               = 'Present'
            Name                 = $SQLAdminUser
            LoginType            = 'WindowsUser'
            ServerName           = $NetBIOSName
            InstanceName         = 'MSSQLSERVER'
        }

        SqlServerLogin 'AddDomainAdmin' {
            Ensure               = 'Present'
            Name                 = $DomainAdminUser
            LoginType            = 'WindowsUser'
            ServerName           = $NetBIOSName
            InstanceName         = 'MSSQLSERVER'
        }

        SqlServerRole 'AddSysadminUsers' {
            Ensure               = 'Present'
            ServerRoleName       = 'sysadmin'
            MembersToInclude     = $DomainAdminUser, $SQLAdminUser
            ServerName           = $NetBIOSName
            InstanceName         = 'MSSQLSERVER'
            DependsOn            = '[SqlServerLogin]AddDomainAdmin', '[SqlServerLogin]AddSQLAdmin'
        }

        SqlServiceAccount 'SetSQLServerAgentUser' {
            ServerName     = $NetBIOSName
            InstanceName   = 'MSSQLSERVER'
            ServiceType    = 'SQLServerAgent'
            ServiceAccount = $SQLCredentials
        }

        SqlServiceAccount 'SetSQLServiceUser' {
            ServerName     = $NetBIOSName
            InstanceName   = 'MSSQLSERVER'
            ServiceType    = 'DatabaseEngine'
            ServiceAccount = $SQLCredentials
        }

        File 'SQLDataFolder' {
            Ensure          = 'Present'
            Type            = 'Directory'
            DestinationPath = 'D:\MSSQL\DATA'
        }
    
        File 'SQLLogFolder' {
            Ensure          = 'Present'
            Type            = 'Directory'
            DestinationPath = 'E:\MSSQL\LOG'
        }
    
        File 'SQLBackupFolder' {
            Ensure          = 'Present'
            Type            = 'Directory'
            DestinationPath = 'F:\MSSQL\Backup'
        }
    
        File 'SQLTempDBFolder' {
            Ensure          = 'Present'
            Type            = 'Directory'
            DestinationPath = 'F:\MSSQL\TempDB'
        }

        SqlDatabaseDefaultLocation 'SqlDatabaseDefaultDataDirectory' {
            ServerName              = $NetBIOSName
            InstanceName            = 'MSSQLSERVER'
            ProcessOnlyOnActiveNode = $true
            Type                    = 'Data'
            Path                    = 'D:\MSSQL\DATA'
            PsDscRunAsCredential    = $SQLCredentials
            DependsOn               = '[SqlServerRole]AddSysadminUsers', '[File]SQLDataFolder'
        }

        SqlDatabaseDefaultLocation 'SqlDatabaseDefaultLogDirectory' {
            ServerName              = $NetBIOSName
            InstanceName            = 'MSSQLSERVER'
            ProcessOnlyOnActiveNode = $true
            Type                    = 'Log'
            Path                    = 'E:\MSSQL\LOG'
            PsDscRunAsCredential    = $SQLCredentials
            DependsOn               = '[SqlServerRole]AddSysadminUsers', '[File]SQLLogFolder'
        }

        SqlDatabaseDefaultLocation 'SqlDatabaseDefaultBackupDirectory' {
            ServerName              = $NetBIOSName
            InstanceName            = 'MSSQLSERVER'
            ProcessOnlyOnActiveNode = $true
            Type                    = 'Backup'
            Path                    = 'F:\MSSQL\Backup'
            PsDscRunAsCredential    = $SQLCredentials
            DependsOn               = '[SqlDatabaseDefaultLocation]SqlDatabaseDefaultDataDirectory', '[SqlDatabaseDefaultLocation]SqlDatabaseDefaultLogDirectory', '[File]SQLTempDBFolder'
        }

        Script 'UpdateStartupSettings' {
            GetScript = {
                [System.Reflection.Assembly]::LoadWithPartialName('Microsoft.SqlServer.SqlWmiManagement')| Out-Null
                $smowmi = New-Object Microsoft.SqlServer.Management.Smo.Wmi.ManagedComputer localhost
                $SQLService = $smowmi.Services | where {$_.name -eq 'MSSQLSERVER'}
                Return @{Result = [string]$($SQLService.StartupParameters)}
            }
            TestScript = {
                [System.Reflection.Assembly]::LoadWithPartialName('Microsoft.SqlServer.SqlWmiManagement')| Out-Null
                $smowmi = New-Object Microsoft.SqlServer.Management.Smo.Wmi.ManagedComputer localhost
                $SQLService = $smowmi.Services | where {$_.name -eq 'MSSQLSERVER'}
                if ($SQLService.StartupParameters -like '-dC:\Program Files\Microsoft SQL Server\MSSQL*.MSSQLSERVER\MSSQL\DATA\master.mdf;-eC:\Program Files\Microsoft SQL Server\MSSQL*.MSSQLSERVER\MSSQL\Log\ERRORLOG;-lC:\Program Files\Microsoft SQL Server\MSSQL*.MSSQLSERVER\MSSQL\DATA\mastlog.ldf') {
                    Write-Verbose 'SQL Service Startup Parameters Still Set to Original Settings'
                    Return $false
                } else {
                    Write-Verbose 'SQL Service Startup Parameter Set to Correctly'
                    Return $true
                }
            }
            SetScript = {
                $sqlpath = (Resolve-Path 'C:\Program Files\Microsoft SQL Server\MSSQL*.MSSQLSERVER\').Path
                $params = "-dD:\MSSQL\DATA\master.mdf;-e$sqlpath\MSSQL\Log\ERRORLOG;-lE:\MSSQL\LOG\mastlog.ldf"
                [System.Reflection.Assembly]::LoadWithPartialName('Microsoft.SqlServer.SqlWmiManagement')| Out-Null
                $smowmi = New-Object Microsoft.SqlServer.Management.Smo.Wmi.ManagedComputer localhost
                $SQLService = $smowmi.Services | where {$_.name -eq 'MSSQLSERVER'}
                $SQLService.StartupParameters = $params
                $SQLService.Alter()
            }
            DependsOn = '[SqlDatabaseDefaultLocation]SqlDatabaseDefaultBackupDirectory'
        }

        SqlScriptQuery 'UpdatePathTempDB' {
            ServerInstance = 'localhost'
            SetQuery       = "USE master; ALTER DATABASE tempdb MODIFY FILE (NAME = tempdev, FILENAME = 'F:\MSSQL\TempDB\tempdb.mdf'); ALTER DATABASE tempdb MODIFY FILE (NAME = templog, FILENAME = 'F:\MSSQL\TempDB\templog.ldf');"
            TestQuery      = "IF NOT EXISTS (SELECT name FROM sys.master_files WHERE physical_name='F:\MSSQL\TempDB\tempdb.mdf' OR physical_name='F:\MSSQL\TempDB\templog.ldf')
            BEGIN
                RAISERROR ('Database Location is not correct', 16, 1)
            END
            ELSE
            BEGIN
                PRINT 'Database Location is set correctly'
            END"
            GetQuery       = "SELECT physical_name FROM sys.master_files WHERE name='tempdev' OR name='templog';"
            PsDscRunAsCredential = $SQLCredentials
            DependsOn            = '[SqlServerRole]AddSysadminUsers'
        }

        SqlScriptQuery 'UpdatePathModel' {
            ServerInstance = 'localhost'
            SetQuery       = "USE master; ALTER DATABASE model MODIFY FILE (NAME = modeldev, FILENAME = 'D:\MSSQL\DATA\model.mdf'); ALTER DATABASE model MODIFY FILE (NAME = modellog, FILENAME = 'E:\MSSQL\LOG\modellog.ldf');"
            TestQuery      = "IF NOT EXISTS (SELECT name FROM sys.master_files WHERE physical_name='D:\MSSQL\DATA\model.mdf' OR physical_name='E:\MSSQL\LOG\modellog.ldf')
            BEGIN
                RAISERROR ('Database Location is not correct', 16, 1)
            END
            ELSE
            BEGIN
                PRINT 'Database Location is set correctly'
            END"
            GetQuery       = "SELECT physical_name FROM sys.master_files WHERE name='modeldev' OR name='modellog';"
            PsDscRunAsCredential = $SQLCredentials
            DependsOn            = '[SqlServerRole]AddSysadminUsers'
        }

        SqlScriptQuery 'UpdatePathMSDB' {
            ServerInstance = 'localhost'
            SetQuery       = "USE master; ALTER DATABASE MSDB MODIFY FILE (NAME = MSDBData, FILENAME = 'D:\MSSQL\DATA\MSDBData.mdf'); ALTER DATABASE MSDB MODIFY FILE (NAME = MSDBLog, FILENAME = 'E:\MSSQL\LOG\MSDBLog.ldf');"
            TestQuery      = "IF NOT EXISTS (SELECT name FROM sys.master_files WHERE physical_name='D:\MSSQL\DATA\MSDBData.mdf' OR physical_name='E:\MSSQL\LOG\MSDBLog.ldf')
            BEGIN
                RAISERROR ('Database Location is not correct', 16, 1)
            END
            ELSE
            BEGIN
                PRINT 'Database Location is set correctly'
            END"
            GetQuery       = "SELECT physical_name FROM sys.master_files WHERE name='MSDBData' OR name='MSDBLog';"
            PsDscRunAsCredential = $SQLCredentials
            DependsOn            = '[SqlServerRole]AddSysadminUsers'
        }

        Script MoveDBFiles {
            GetScript = {
                [array]$filelocations = "F:\MSSQL\TempDB\tempdb.mdf","F:\MSSQL\TempDB\templog.ldf","D:\MSSQL\DATA\model.mdf","E:\MSSQL\LOG\modellog.ldf","D:\MSSQL\DATA\MSDBData.mdf","E:\MSSQL\LOG\MSDBLog.ldf","D:\MSSQL\DATA\master.mdf","E:\MSSQL\LOG\mastlog.ldf"
                Return @{Result = [string]$(test-path $filelocations)}
            }
            TestScript = {
                [array]$filelocations = "F:\MSSQL\TempDB\tempdb.mdf","F:\MSSQL\TempDB\templog.ldf","D:\MSSQL\DATA\model.mdf","E:\MSSQL\LOG\modellog.ldf","D:\MSSQL\DATA\MSDBData.mdf","E:\MSSQL\LOG\MSDBLog.ldf","D:\MSSQL\DATA\master.mdf","E:\MSSQL\LOG\mastlog.ldf"
                if(((test-path $filelocations) -eq $false).Count) {
                    Write-Verbose 'Files need to be Moved'
                    Return $false
                } else {
                    Write-Verbose 'File Locations are correct'
                    Return $true
                }
            }
            SetScript = {
                # Stop SQL Service
                $SQLService = Get-Service -Name 'MSSQLSERVER'
                if ($SQLService.status -eq 'Running') {$SQLService.Stop()}
                $SQLService.WaitForStatus('Stopped','00:01:00')
                # Move files to new locations
                Move-Item "C:\Program Files\Microsoft SQL Server\MSSQL*.MSSQLSERVER\MSSQL\DATA\tempdb.mdf" "F:\MSSQL\TempDB\tempdb.mdf"
                Move-Item "C:\Program Files\Microsoft SQL Server\MSSQL*.MSSQLSERVER\MSSQL\DATA\templog.ldf" "F:\MSSQL\TempDB\templog.ldf"
                Move-Item "C:\Program Files\Microsoft SQL Server\MSSQL*.MSSQLSERVER\MSSQL\DATA\model.mdf" "D:\MSSQL\DATA\model.mdf"
                Move-Item "C:\Program Files\Microsoft SQL Server\MSSQL*.MSSQLSERVER\MSSQL\DATA\modellog.ldf" "E:\MSSQL\LOG\modellog.ldf"
                Move-Item "C:\Program Files\Microsoft SQL Server\MSSQL*.MSSQLSERVER\MSSQL\DATA\MSDBData.mdf" "D:\MSSQL\DATA\MSDBData.mdf"
                Move-Item "C:\Program Files\Microsoft SQL Server\MSSQL*.MSSQLSERVER\MSSQL\DATA\MSDBLog.ldf" "E:\MSSQL\LOG\MSDBLog.ldf"
                Move-Item "C:\Program Files\Microsoft SQL Server\MSSQL*.MSSQLSERVER\MSSQL\DATA\master.mdf" "D:\MSSQL\DATA\master.mdf"
                Move-Item "C:\Program Files\Microsoft SQL Server\MSSQL*.MSSQLSERVER\MSSQL\DATA\mastlog.ldf" "E:\MSSQL\LOG\mastlog.ldf"
                # Start service4
                $SQLService.Start()
                $SQLService.WaitForStatus('Running','00:01:00')
            }
            DependsOn = '[SqlDatabaseDefaultLocation]SqlDatabaseDefaultBackupDirectory'
        }
    }
}

ReconfigureSQL -OutputPath 'C:\AWSQuickstart\ReconfigureSQL' -Credentials $Credentials -SQLCredentials $SQLCredentials -ConfigurationData $ConfigurationData

Start-DscConfiguration 'C:\AWSQuickstart\ReconfigureSQL' -Wait -Verbose -Force