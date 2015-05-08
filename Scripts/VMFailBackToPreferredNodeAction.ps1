#===================================================================================================
# AUTHOR:         	Tao Yang
# Script Name:    	VMFailBackToPreferredNodeAction.ps1
# DATE:           	11/07/2012
# Version:        	1.0
# COMMENT:			- Script to fail back Virtual Machines on a Hyper-V Cluster to a preferred host
#===================================================================================================
Param (
	[string]$ClusterName,
	[string]$VirtualMachines
	)

Function Get-OnePreferredHost($ClusterName, $ClusterResourceName)
{
	$arrPreferredHosts = Get-WmiObject -Computer $ClusterName -Namespace root\MSCluster -Query "Associators of {MSCluster_ResourceGroup.Name='$ClusterResourceName'} WHERE AssocClass = MSCluster_ResourceGroupToPreferredNode"
	$PreferredHost = Get-Random -InputObject $arrPreferredHosts
	$PreferredHostName = $PreferredHost.Name
	$PreferredHostName
}

Function Get-CurrentHost ($ClusterName, $ClusterResourceName)
{
	$CurrentHost = (Get-WmiObject -ComputerName $ClusterName -Namespace root\MSCluster -Query "Associators of {MSCluster_ResourceGroup.Name='$ClusterResourceName'} WHERE AssocClass = MSCluster_NodeToActiveGroup").Name
	$CurrentHost
}

$arrVirtualMachines = $VirtualMachines.split(";")

Foreach ($VM in $arrVirtualMachines)
{
	#Write-Host $VM
	
	$Target = Get-OnePreferredHost $ClusterName $VM
	
	#$VMResourceGroup = Get-WmiObject -Namespace root\MSCluster -Query "Associators of {MSCluster_Resource.Name='$($VMResource.Name)'} WHERE AssocClass = MSCluster_ResourceGroupToResource"
	Write-Host "Preferred Host for $VM is $Target"
	$VMResourceGroup = Get-WmiObject -ComputerName $ClusterName -Namespace root\MSCluster -Query "Select * from MSCluster_ResourceGroup Where Name = '$VM'"
	$VMResources = Get-WmiObject -ComputerName $ClusterName -Namespace root\MSCluster -Query "Associators of {MSCluster_ResourceGroup.Name='$($VMResourceGroup.Name)'} WHERE AssocClass = MSCluster_ResourceGroupToResource"
	Foreach ($VMResource in $VMResources)
	{
		if ($VMResource.Type -eq 'Virtual Machine')
		{
			$CurrentHost = Get-CurrentHost $ClusterName $VM
			Write-Host "Moving $VM Resource from $CurrentHost to $Target`..."
			$EncodedTarget = [System.Text.Encoding]::UNICODE.GetBytes($Target)
			$ResourceControlCode = 23068676
			#$LiveMigrationJob = Invoke-WmiMethod -InputObject $VMResource -Name ExecuteResourceControl -ArgumentList $ResourceControlCode, $Target -AsJob
			$VMResource.ExecuteResourceControl(23068676,$EncodedTarget) | Out-Null
			$bJobCompleted = $false
			do {
				Start-Sleep -Seconds 5
				$CurrentHost = Get-CurrentHost $ClusterName $VM
				if ($CurrentHost -ieq $Target)
				{
					$bJobCompleted = $true
				}
			}
			While ($bJobCompleted -eq $false)
			#$VMResourceGroup.MoveToNewNode($PreferredHostName, $MoveToNewNodeTimeoutSeconds)
		}
	}
}
Write-Host "Done!"
