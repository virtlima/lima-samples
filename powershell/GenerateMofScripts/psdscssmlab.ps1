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
# PowerShell DSC Configuration Function
configuration ssmlab {
    # Importing DSC Resource used in the Configuration 
    Import-DscResource -ModuleName PSDscResources
    Import-DscResource -ModuleName SecurityPolicyDsc
    
    Node 'localhost'{
        # Configures the Interactive Logon Message
        SecurityOption LogonMessage {
            Name = "LogonMessage"
            Interactive_logon_Message_title_for_users_attempting_to_log_on = 'Logon policy From SSM'
            Interactive_logon_Message_text_for_users_attempting_to_log_on = '{ssm:/WinWorkshop/LogonMessage}'
        }
        # Installs IIS
        WindowsFeature WebServer {
            Ensure = "Present"
            Name   = "Web-Server"
        }
    }
}
# Create the MOF File from the Configuration Function
ssmlab -OutputPath 'C:\MofFiles' -ConfigurationData $ConfigurationData