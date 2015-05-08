#===========================================================================================
# AUTHOR:         	Tao Yang
# Script Name:    	VMPreferredHostWMIProbe.ps1
# DATE:           	03/07/2012
# Version:        	1.5
# COMMENT:			- Script to check if Hyper-V guest VM is located on the preferred host
#===========================================================================================
#get host name
$HostName = $env:COMPUTERNAME

#This Script
$ScriptName = "VMPreferredHostWMIProbe.ps1"
#MOM API
$oAPI = New-Object -ComObject "MOM.ScriptAPI"

#Debugging Log
$OAPI.LogScriptEvent($ScriptName,11000,0,"Hyper-V Cluster VM Preferred Host Probe script is being executed on $HostName`...")

#PS array for virtual machines that are located on the wrong host
$arrVMsOnWrongHost = @()
$arrVMsOnPreferredHost = @()
$arrPreferredHostsNotConfigured = @()
#$arrIncorrectPreferredOwner = @()

#Get virtual machines cluster resources that are currently hosted on the local cluster node (this computer)
$arrVirtualMachines = Get-WmiObject -Namespace root\MSCluster -Query "Select * from MSCluster_Resource Where Type = 'Virtual Machine'"
$bAllVMsOnPreferredHost = $true
$bAllVMsPreferredHostConfigured = $true

foreach ($VirtualMachine in $arrVirtualMachines)
{
    $VMResourceGroup = Get-WmiObject -Namespace root\MSCluster -Query "Associators of {MSCluster_Resource.Name='$($VirtualMachine.Name)'} WHERE AssocClass = MSCluster_ResourceGroupToResource"
	$VirtualMachineName = $VMResourceGroup.Name
	$CurrentResourceOwner = Get-WmiObject -Namespace root\MSCluster -Query "Associators of {MSCluster_ResourceGroup.Name='$($VMResourceGroup.Name)'} WHERE AssocClass = MSCluster_NodeToActiveGroup"
	$arrPreferredOwners = Get-WmiObject -Namespace root\MSCluster -Query "Associators of {MSCluster_ResourceGroup.Name='$($VMResourceGroup.Name)'} WHERE AssocClass = MSCluster_ResourceGroupToPreferredNode"
	#Determine if the current resource owner is one of the preferred owners
	if ($arrPreferredOwners)
	{
		$IsOnPreferredHost = $false
		Foreach ($PreferredOwner in $arrPreferredOwners)
		{
			if ($PreferredOwner.Name -ieq $CurrentResourceOwner.Name)
			{
				$IsOnPreferredHost = $true
				#add the VM to $arrVMsOnPreferredHost
				$arrVMsOnPreferredHost += $VirtualMachineName
				$bAllVMsPreferredHostConfigured = $false
			}
		}
	} else {
		#Preferred host not configured for this VM. consider as is on preferred host
		$IsOnPreferredHost = $true
		#Add the VM to $arrPreferredHostsNotConfigured
		$arrPreferredHostsNotConfigured += $VirtualMachineName
	}
	
	#If the VM is not on the preferred owner, add to the $arrVMsOnWrongHost array and change $bAllVMsOnPreferredOwner to False
	If (!$IsOnPreferredHost)
	{
		$bAllVMsOnPreferredHost = $false
		$arrVMsOnWrongHost += $VirtualMachineName
	}
}

#Convert VM On Wrong Host array to string - separated by ";"
$strVMsOnWrongHost = [system.String]::Join(";", $arrVMsOnWrongHost)

#Convert VM On Preferred Host array to string - separated by ";"
$strVMsOnPreferredHost = [system.String]::Join(";", $arrVMsOnPreferredHost)

#Convert Preferred Host Not Set array to string - separated by ";"
$strPreferredHostsNotConfigured = [system.String]::Join(";", $arrPreferredHostsNotConfigured)

#MOM API PropertyBag
$oBag = $oAPI.CreatePropertyBag()
$oBag.AddValue('VMsOnWrongHost', $strVMsOnWrongHost)
$oBag.AddValue('VMsOnPreferredHost', $strVMsOnPreferredHost)
$oBag.AddValue('PreferredHostsNotConfigured', $strPreferredHostsNotConfigured)
$oBag.AddValue('AllVMsOnPreferredHost', $bAllVMsOnPreferredHost)
$oBag.AddValue('AllVMsPreferredHostConfigured', $bAllVMsPreferredHostConfigured)

#Debugging Log
if ($bAllVMsOnPreferredHost)
{
	$OAPI.LogScriptEvent($ScriptName,11001,0,"All virtual machines are on preferred hosts: $strVMsOnPreferredHost")
} else {
	$OAPI.LogScriptEvent($ScriptName,11003,2,"At least 1 virtual machine is not on preferred hosts")
}

if ($strVMsOnPreferredHost.length -gt 0)
{
	$OAPI.LogScriptEvent($ScriptName,11002,0,"The following virtual machines are on the preferred host: $strVMsOnPreferredHost")
}

if ($strVMsOnWrongHost.length -gt 0)
{
	$OAPI.LogScriptEvent($ScriptName,11004,2,"The following virtual machines are NOT on the preferred host: $strVMsOnWrongHost")
}

#return property bag
$oBag
#$oAPI.Return($oBag)
