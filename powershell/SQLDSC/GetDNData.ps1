[CmdletBinding()]
param(

    [Parameter(Mandatory=$true)]
    [string]$DomainNetBIOSName,

    [Parameter(Mandatory=$true)]
    [string]$DomainDNSName,

    [Parameter(Mandatory=$true)]
    [string]$AdminSecret
)

$AdminUser = ConvertFrom-Json -InputObject (Get-SECSecretValue -SecretId $AdminSecret).SecretString
$Credentials = (New-Object PSCredential($ClusterAdminUser,(ConvertTo-SecureString $AdminUser.Password -AsPlainText -Force)))

Function Get-Domain {
	
	#Retrieve the Fully Qualified Domain Name if one is not supplied
	# division.domain.root
	if ($DomainDNSName -eq "") {
		[String]$DomainDNSName = [System.DirectoryServices.ActiveDirectory.Domain]::getcurrentdomain()
    }
    
    $DN = get-addomain $DomainDNSName | select distinguishedname
	return $DN
}

Function Convert-CidrtoSubnetMask { 
    Param ( 
        [String] $SubnetMaskCidr
    ) 

    Function Convert-Int64ToIpAddress() { 
      Param 
      ( 
          [int64] 
          $Int64 
      ) 
   
      # Return 
      '{0}.{1}.{2}.{3}' -f ([math]::Truncate($Int64 / 16777216)).ToString(), 
          ([math]::Truncate(($Int64 % 16777216) / 65536)).ToString(), 
          ([math]::Truncate(($Int64 % 65536)/256)).ToString(), 
          ([math]::Truncate($Int64 % 256)).ToString() 
    } 
 
    # Return
    Convert-Int64ToIpAddress -Int64 ([convert]::ToInt64(('1' * $SubnetMaskCidr + '0' * (32 - $SubnetMaskCidr)), 2)) 
}

Function Get-CIDR {
    Param ( 
        [String] $Target
    ) 
    Invoke-Command -ComputerName $Target -Credential $Credentials -Scriptblock {(Get-NetIPConfiguration).IPv4Address.PrefixLength[0]}
}
