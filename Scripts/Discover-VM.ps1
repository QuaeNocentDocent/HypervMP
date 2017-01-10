#TO SHOW VERBOSE MESSAGES SET $VerbosePreference="continue"
#SET ErrorLevel to 5 so show discovery info

#*************************************************************************
# Script Name - Discover-VM.ps1
# Author	  -  - Progel spa
# Version  - 24.09.2007
# Purpose     - 
#               
# Assumptions - 
#				
#               
# Parameters  - TraceLevel
#             - ComputerName
#				- SourceId
#				- ManagedEntityId
# Command Line - .\test.ps1 4 "serverName" '{1860E0EB-8C21-41DA-9F35-2FE9343CCF36}' '{1860E0EB-8C21-41DA-9F35-2FE9343CCF36}'
# If discovery must be added the followinf parameters
#				SourceId ($ MPElement $ )
#				ManagedEntityId ($ Target/Id $)
#
# Output properties
#
# Status
#
# $Version$ History
#	  1.0 06.08.2010 DG First Release
#     1.5 15.02.2014 DG minor cosmetics
#
# (c) Copyright 2015, Progel spa, All Rights Reserved
# Proprietary and confidential to Progel srl              
#
#*************************************************************************


# Get the named parameters
param([int]$traceLevel=$(throw 'must have a value'),
[string]$HostComputerIdentity=$(throw 'must have a value'),
[string]$sourceID=$(throw 'must have a value'),
[string]$ManagedEntityId=$(throw 'must have a value'))

	[Threading.Thread]::CurrentThread.CurrentCulture = "en-US"        
	[Threading.Thread]::CurrentThread.CurrentUICulture = "en-US"
	
#Constants used for event logging
$SCRIPT_NAME			= "Discover-VM.ps1"
$SCRIPT_ARGS = 4
$SCRIPT_STARTED			= 831
$PROPERTYBAG_CREATED	= 832
$SCRIPT_ENDED			= 835
$SCRIPT_VERSION = "1.0"

#region Constants
#Trace Level Costants
$TRACE_NONE 	= 0
$TRACE_ERROR 	= 1
$TRACE_WARNING = 2
$TRACE_INFO 	= 3
$TRACE_VERBOSE = 4
$TRACE_DEBUG = 5

#Event Type Constants
$EVENT_TYPE_SUCCESS      = 0
$EVENT_TYPE_ERROR        = 1
$EVENT_TYPE_WARNING      = 2
$EVENT_TYPE_INFORMATION  = 4
$EVENT_TYPE_AUDITSUCCESS = 8
$EVENT_TYPE_AUDITFAILURE = 16

#Standard Event IDs
$FAILURE_EVENT_ID = 4000		#errore generico nello script
$SUCCESS_EVENT_ID = 1101
$START_EVENT_ID = 1102
$STOP_EVENT_ID = 1103

#TypedPropertyBag
$AlertDataType = 0
$EventDataType	= 2
$PerformanceDataType = 2
$StateDataType       = 3
#endregion

#region Helper Functions
function Log-Params
{
	param($Invocation)
	$line=''
	foreach($key in $Invocation.BoundParameters.Keys) {$line += "$key=$($Invocation.BoundParameters[$key])  "}
	Log-Event $START_EVENT_ID $EVENT_TYPE_INFORMATION  ("Starting script. Invocation Name:$($Invocation.InvocationName)`n Parameters`n $line") $TRACE_INFO
}


function Log-Event
{
	param($eventID, $eventType, $msg, $level)
	
	Write-Verbose ("Logging event. " + $SCRIPT_NAME + " EventID: " + $eventID + " eventType: " + $eventType + " Version:" + $SCRIPT_VERSION + " --> " + $msg)
	if($level -le $P_TraceLevel)
	{
		Write-Host ("Logging event. " + $SCRIPT_NAME + " EventID: " + $eventID + " eventType: " + $eventType + " Version:" + $SCRIPT_VERSION + " --> " + $msg)
		$g_API.LogScriptEvent($SCRIPT_NAME,$eventID,$eventType, ($msg + "`n" + "Version :" + $SCRIPT_VERSION))
	}
}

Function Throw-EmptyDiscovery
{
	param($SourceId, $ManagedEntityId)

	$oDiscoveryData = $g_API.CreateDiscoveryData(0, $SourceId, $ManagedEntityId)
	Log-Event $FAILURE_EVENT_ID $EVENT_TYPE_WARNING "Exiting with empty discovery data" $TRACE_INFO
	$oDiscoveryData
	If($traceLevel -eq $TRACE_DEBUG)
	{
		#just for debug proposes when launched from command line does nothing when run inside OpsMgr Agent
		$g_API.Return($oDiscoveryData)
	}
}

Function Throw-KeepDiscoveryInfo
{
param($SourceId, $ManagedEntityId)
	$oDiscoveryData = $g_API.CreateDiscoveryData(0,$SourceId,$ManagedEntityId)
	#Instead of Snapshot discovery, submit Incremental discovery data
	$oDiscoveryData.IsSnapshot = $false
	Log-Event $FAILURE_EVENT_ID $EVENT_TYPE_WARNING "Exiting with null non snapshot discovery data" $TRACE_INFO
	$oDiscoveryData    
	If($traceLevel -eq $TRACE_DEBUG)
	{
		#just for debug proposes when launched from command line does nothing when run inside OpsMgr Agent	
		$g_API.Return($oDiscoveryData)
	}
}
#endregion


Function NullIsFalse
{
	param($value)
	if(! $value) {return $false}
	return $value
}

Function NullIsZero
{
	param($value)
	if(! $value) {return 0}
	return $value
}

Function Get-KVPData
{
	param($propList, $key)
	if(! $propList) {return $null}
	$elem = $propList | where {([xml]$_).SelectSingleNode("/INSTANCE/PROPERTY[@NAME='Name']/VALUE[child::text()='$key']")}
	if ($elem) {
		$xmlData = ([xml]$elem).SelectSingleNode("/INSTANCE/PROPERTY[@NAME='Data']/VALUE[child::text()]")
		if ($xmlData) {return $xmlData.Innertext}
	}
	return $null
}

#Start by setting up API object.
	$P_TraceLevel = $TRACE_VERBOSE
	$g_Api = New-Object -comObject 'MOM.ScriptAPI'
	#$g_RegistryStatePath = "HKLM\" + $g_API.GetScriptStateKeyPath($SCRIPT_NAME)

	$dtStart = Get-Date
	$P_TraceLevel = $traceLevel
	Log-Params $MyInvocation

try
{

	if (!(get-Module -Name Hyper-v)) {Import-Module Hyper-v -ErrorAction SilentlyContinue}
	if (!(get-Module -Name failoverclusters)) {Import-Module failoverclusters -ErrorAction SilentlyContinue}
	$HVFarm = $HostComputerIdentity
	try {
		if((get-module -Name failoverclusters)) {
			$cluster = get-cluster -ErrorAction SilentlyContinue
			if($cluster) {$HVFarm="$($cluster.Name).$($cluster.Domain)"}
		}
	}
	catch [Exception] {
		#do nothing
	}
	if (!(get-command -Module Hyper-V -Name Get-VM -ErrorAction SilentlyContinue)) {
		Log-Event $START_EVENT_ID $EVENT_TYPE_WARNING ("Get-VM Commandlet doesn't exist.") $TRACE_WARNING
		Throw-EmptyDiscovery
	}
	$oDiscoveryData = $g_api.CreateDiscoveryData(0, $sourceId, $managedEntityId)
	$VMs=Get-VM
	foreach($vm in $vms) {
		try {
			$wmiVM = gwmi -Namespace root\virtualization\v2 -Class Msvm_ComputerSystem -Filter "Name='$($vm.VMId)'"
			if($wmiVM) {
				$PropList = $wmivm.GetRelated("Msvm_KvpExchangeComponent").GuestIntrinsicExchangeItems
				$computerName = Get-KVPData -propList $PropList -key 'FullyQualifiedDomainName'
				$OSPlatformId = Get-KVPData -propList $PropList -key 'OSPlatformId'
				$OSName = Get-KVPData -propList $PropList -key 'OSName'
				$OSVersion = Get-KVPData -propList $PropList -key 'OSVersion'
			}

			$oInstance = $oDiscoveryData.CreateClassInstance("$MPElement[Name='QND.Hyperv.2012R2.VM']$")
			$oInstance.AddProperty("$MPElement[Name='System!System.Entity']/DisplayName$", $vm.VMName)		  
			$oInstance.AddProperty("$MPElement[Name='SHL!System.ComputerHardware']/NumberOfProcessors$",  (NullIsZero $vm.ProcessorCount))
			$oInstance.AddProperty("$MPElement[Name='SHL!System.ComputerHardware']/Model$",  'Virtual Machine')	
			$oInstance.AddProperty("$MPElement[Name='SHL!System.ComputerHardware']/Manufacturer$",  'Microsoft Hyper-V')	
			$oInstance.AddProperty("$MPElement[Name='QND.Hyperv.2012R2.VM']/HostName$", $HostComputerIdentity)
			$oInstance.AddProperty("$MPElement[Name='QND.Hyperv.2012R2.VM']/VirtualMachineId$", $vm.Id.ToString())
			$oInstance.AddProperty("$MPElement[Name='QND.Hyperv.2012R2.VM']/VirtualMachineName$", $vm.VMName)

			if($vm.IntegrationServicesVersion) {$oInstance.AddProperty("$MPElement[Name='QND.Hyperv.2012R2.VM']/ISVersion$", $vm.IntegrationServicesVersion.ToString())}
			$oInstance.AddProperty("$MPElement[Name='QND.Hyperv.2012R2.VM']/RMEnabled$", (NullIsFalse $vm.ResourceMeteringEnabled))
			$oInstance.AddProperty("$MPElement[Name='QND.Hyperv.2012R2.VM']/VMGeneration$", (NullIsZero $vm.Generation))
			$oInstance.AddProperty("$MPElement[Name='QND.Hyperv.2012R2.VM']/HA$", (NullIsFalse $vm.IsClustered))
	#there's a bug in HypervPOSH for fixed memory VMs, sometimes wrong values are returned for minimum and maximum memory
			if($vm.DynamicMemoryEnabled) {
				$oInstance.AddProperty("$MPElement[Name='QND.Hyperv.2012R2.VM']/MinMemory$", (NullIsZero ($vm.MemoryMinimum/1MB)))
				$oInstance.AddProperty("$MPElement[Name='QND.Hyperv.2012R2.VM']/MaxMemory$", (NullIsZero ($vm.MemoryMaximum/1MB)))
				$oInstance.AddProperty("$MPElement[Name='QND.Hyperv.2012R2.VM']/StartMemory$", (NullIsZero ($vm.MemoryStartup/1MB)))
			}
			else {
				$oInstance.AddProperty("$MPElement[Name='QND.Hyperv.2012R2.VM']/MinMemory$", (NullIsZero ($vm.MemoryStartup/1MB)))
				$oInstance.AddProperty("$MPElement[Name='QND.Hyperv.2012R2.VM']/MaxMemory$", (NullIsZero ($vm.MemoryStartup/1MB)))
				$oInstance.AddProperty("$MPElement[Name='QND.Hyperv.2012R2.VM']/StartMemory$", (NullIsZero ($vm.MemoryStartup/1MB)))
			}
			if((NullIsFalse $vm.IsClustered) -eq $true) {$oInstance.AddProperty("$MPElement[Name='QND.Hyperv.2012R2.VM']/HVFarm$", $HVFarm)}
			else {$oInstance.AddProperty("$MPElement[Name='QND.Hyperv.2012R2.VM']/HVFarm$", $HostComputerIdentity)}

			if (![String]::IsNullOrEmpty($computerName)) {$oInstance.AddProperty("$MPElement[Name='QND.Hyperv.2012R2.VM']/VMComputerName$", $computerName)}
			if (![String]::IsNullOrEmpty($OSName))	{$oInstance.AddProperty("$MPElement[Name='QND.Hyperv.2012R2.VM']/OSName$", $OSName)}
			if (![String]::IsNullOrEmpty($OSVersion))	{$oInstance.AddProperty("$MPElement[Name='QND.Hyperv.2012R2.VM']/OSVersion$", $OSVersion)}

			if (![String]::IsNullOrEmpty($OSPlatformId))
			{
				$oInstance.AddProperty("$MPElement[Name='QND.Hyperv.2012R2.VM']/OSPlatformId$", [int]$OSPlatformId)
				If($OSPlatformId -eq 2) {$oInstance.AddProperty("$MPElement[Name='QND.Hyperv.2012R2.VM']/OSFamily$", 'Windows')}
				else {$oInstance.AddProperty("$MPElement[Name='QND.Hyperv.2012R2.VM']/OSFamily$", 'Linux')}
			}

			$oDiscoveryData.AddInstance($oInstance);

			#Create HealthService Relationship
			#Discover HealthService
			$healthservice = $oDiscoveryData.CreateClassInstance("$MPElement[Name='SC!Microsoft.SystemCenter.HealthService']$")
			$healthservice.AddProperty("$MPElement[Name='Windows!Microsoft.Windows.Computer']/PrincipalName$", $HostComputerIdentity)
			$oDiscoveryData.AddInstance($healthService)
			#Create HealthServiceShouldManageEntity Relationship
			$rel = $oDiscoveryData.CreateRelationshipInstance("$MPElement[Name='SC!Microsoft.SystemCenter.HealthServiceShouldManageEntity']$")
			$Rel.Source=$HealthService
			$Rel.Target=$oInstance
			$oDiscoveryData.AddInstance($Rel)

			#discover disks
			$diskDetails = Get-VHD -VMId $vm.VMId
			foreach($disk in $vm.HardDrives) {
				$oDisk = $oDiscoveryData.CreateClassInstance("$MPElement[Name='QND.HyperV.2012R2.VirtualDrive']$")	
				$oDisk.AddProperty("$MPElement[Name='QND.Hyperv.2012R2.VM']/VirtualMachineId$", $vm.Id.ToString())	
				$oDisk.AddProperty("$MPElement[Name='System!System.Entity']/DisplayName$", "$($vm.Name) - $($disk.Name)")		
				$oDisk.AddProperty("$MPElement[Name='QND.HyperV.VMHardwareComponent']/DeviceId$", $disk.Id)
				$oDisk.AddProperty("$MPElement[Name='QND.HyperV.VMHardwareComponent']/Name$", $disk.Name)
				if($disk.ControllerType) {$oDisk.AddProperty("$MPElement[Name='QND.HyperV.2012R2.VirtualDrive']/ConnectedControllerName$", $disk.ControllerType.ToString())}
				$oDisk.AddProperty("$MPElement[Name='QND.HyperV.2012R2.VirtualDrive']/ImageFile$", $disk.Path)
				#Fix UNC perf counter path
				try {
					if (([Uri]$disk.Path).IsUnc -eq $true) {
						$perfInstance = $disk.Path.Replace('\','-').Insert(2,'?-UNC-')
					} else {
						$perfInstance = $disk.Path.Replace('\','-')
					}
				}
				catch {$perfInstance=''}				
				$oDisk.AddProperty("$MPElement[Name='QND.HyperV.VMHardwareComponent']/PerfInstance$", $perfInstance )
				
				$details = $diskDetails | where {$_.Path -ieq $disk.Path}
				If($details) {
					if($details.VhdFormat) {$oDisk.AddProperty("$MPElement[Name='QND.HyperV.2012R2.VirtualDrive']/VHDFormat$", $details.VhdFormat.ToString())}
					if($details.VhdType) {$oDisk.AddProperty("$MPElement[Name='QND.HyperV.2012R2.VirtualDrive']/VHDType$", $details.VhdType.ToString())}
					$oDisk.AddProperty("$MPElement[Name='QND.HyperV.2012R2.VirtualDrive']/MaxSizeGB$", (NullIsZero ($details.Size/1GB)))
				}
				$oDiscoveryData.AddInstance($oDisk)
				#$rel = $oDiscoveryData.CreateRelationshipInstance("$MPElement[Name='QND.Hyperv.2012R2.VMHostsVMHardwareComponent']$")
				#$Rel.Source=$oInstance
				#$Rel.Target=$oDisk
				#$oDiscoveryData.AddInstance($Rel)
			}

			foreach($nic in $vm.NetworkAdapters) {
				$oNic = $oDiscoveryData.CreateClassInstance("$MPElement[Name='QND.HyperV.2012R2.VirtualNetworkAdapter']$")	
				$oNic.AddProperty("$MPElement[Name='QND.Hyperv.2012R2.VM']/VirtualMachineId$", $vm.Id.ToString())		
				$oNic.AddProperty("$MPElement[Name='System!System.Entity']/DisplayName$", "$($vm.Name) - $($nic.Name) on $($nic.SwitchName)")	
				$oNic.AddProperty("$MPElement[Name='QND.HyperV.VMHardwareComponent']/DeviceId$", $nic.Id)
				$oNic.AddProperty("$MPElement[Name='QND.HyperV.VMHardwareComponent']/Name$", "$($nic.Name) on $($nic.SwitchName)")
				if($nic.SwitchId) {$oNic.AddProperty("$MPElement[Name='QND.HyperV.2012R2.VirtualNetworkAdapter']/SwitchId$", $nic.SwitchId.ToString())}
				$oNic.AddProperty("$MPElement[Name='QND.HyperV.2012R2.VirtualNetworkAdapter']/SwitchName$", $nic.SwitchName)
				try {$perfInstance = ("$($vm.Name)_$($nic.Name)_$($vm.Id.ToString())--$($nic.AdapterId.ToString())").Replace('\','--')}
				catch {$perfInstance=''}
				$oNic.AddProperty("$MPElement[Name='QND.HyperV.VMHardwareComponent']/PerfInstance$", $perfInstance)
				$oDiscoveryData.AddInstance($oNic)
				#$rel = $oDiscoveryData.CreateRelationshipInstance("$MPElement[Name='QND.Hyperv.2012R2.VMHostsVMHardwareComponent']$")
				#$Rel.Source=$oInstance
				#$Rel.Target=$oNic
				#$oDiscoveryData.AddInstance($Rel)
			
			}
	
			Log-Event $STOP_EVENT_ID $EVENT_TYPE_SUCCESS ("$($vm.VMName) has been discovered on $HostComputerIdentity") $TRACE_INFO
		}
		Catch [Exception] {
			Log-Event $STOP_EVENT_ID $EVENT_TYPE_ERROR ("Failed to discover $($vm.VMName) on $HostComputerIdentity $($Error[0].Exception)") $TRACE_ERROR
		}
	}

	$oDiscoveryData
	If ($traceLevel -eq $TRACE_DEBUG)
	{
		#just for debug proposes when launched from command line does nothing when run inside OpsMgr Agent	
		#it breaks in exception when run insde OpsMgr and POSH IDE	
		$g_API.Return($oDiscoveryData)
	}

	Log-Event $STOP_EVENT_ID $EVENT_TYPE_SUCCESS ("has completed successfully in " + ((Get-Date)- ($dtstart)).TotalSeconds + " seconds.") $TRACE_INFO
}
Catch [Exception] {
	Log-Event $FAILURE_EVENT_ID $EVENT_TYPE_ERROR ("Fatal Error in Main $($Error[0].Exception)") $TRACE_ERROR	
	write-Verbose $("TRAPPED: " + $_.Exception.GetType().FullName); 
	Write-Verbose $("TRAPPED: " + $_.Exception.Message); 
}				  



