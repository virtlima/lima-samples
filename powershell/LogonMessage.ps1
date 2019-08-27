[CmdletBinding()]
# Incoming Parameters for Script, CloudFormation\SSM Parameters being passed in
param()

# Creating Configuration Data Block that has the Certificate Information for DSC Configuration Processing
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

configuration LogonMessage {
    Import-DscResource -ModuleName SecurityPolicyDsc
    $multiLineMessage = '{ssm:LogonMessage}'

    Node 'localhost'{
        SecurityOption LogonMessage {
            Name = "Message Test"
            Interactive_logon_Message_text_for_users_attempting_to_log_on = $multiLineMessage
        }

        Group Administrators {
            GroupName = 'Administrators'
            Ensure = 'Present'
            MembersToInclude = @('{ssm:AdministratorUsers}')
        }
    }
}

LogonMessage -OutputPath 'C:\MofFiles\LogonMessage' -ConfigurationData $ConfigurationData