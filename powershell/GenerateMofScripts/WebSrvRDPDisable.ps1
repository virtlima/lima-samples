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

Configuration StdBuild {

    # Import the module that contains the resources we're using.
    Import-DscResource -ModuleName PsDesiredStateConfiguration, xRemoteDesktopAdmin, NetworkingDsc

    # The Node statement specifies which targets this configuration will be applied to.
    Node 'localhost' {
        
        # The first resource block ensures that the Web-Server (IIS) feature is enabled.
        WindowsFeature WebServer {
            Ensure = "Present"
            Name   = "Web-Server"
        }
        
        xRemoteDesktopAdmin RemoteDesktopSettings {
           Ensure = 'Absent'
           UserAuthentication = 'Secure'
        }

        Firewall DisableRDPRule {
            Name                  = 'RemoteDesktop-UserMode-In-TCP'
            Group                 = 'Remote Desktop'
            Ensure                = 'Present'
            Enabled               = 'False'
        }
    }
}

StdBuild -OutputPath 'C:\MofFiles\StdBuild' -ConfigurationData $ConfigurationData
