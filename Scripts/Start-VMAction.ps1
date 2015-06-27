#TO SHOW VERBOSE MESSAGES SET $VerbosePreference="continue"
#SET ErrorLevel to 5 so show discovery info

#*************************************************************************
# Script Name - Start-VMAction.ps1
# Author	  -  - Progel spa
# Version  - 1.0 24.09.2007
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
# Version History
#	  1.0 21.02.2015 DG First Release
#     
#
# (c) Copyright 2015, Progel spa, All Rights Reserved
# Proprietary and confidential to Progel srl              
#
#*************************************************************************


# Get the named parameters
param([int]$traceLevel=$(throw 'must have a value'),
	[string]$VMId,
	[String] $op,
	[string] $param1)


	[Threading.Thread]::CurrentThread.CurrentCulture = "en-US"        
	[Threading.Thread]::CurrentThread.CurrentUICulture = "en-US"
	
#Constants used for event logging
$SCRIPT_NAME			= "Get-VMUptime.ps1"
$SCRIPT_ARGS = 1
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

$vm = get-VM -Id $VMId
if (!$vm) {
	Throw '$VMId Not Found' #so the task terminates in error
}

#jobs don't work in OpMgr POSH environment so I start the commands synchronously
Log-Event $SUCCESS_EVENT_ID $EVENT_TYPE_INFORMATION "Applying action $op to $($vm.Name)" $TRACE_INFO
Write-Host "Applying action $op to $($vm.Name)"
try {
	switch ($op) {
		'restart' {
			Write-Host 'Stopping VM'
			Stop-VM -VM $vm -Verbose -Force
			do {
				Start-Sleep -Seconds 30
				$status = Get-VM -Id $vm.Id
			} while ([int] ($status.state) -ne 3) #3 = Off
			Write-Host 'Starting VM'
			Start-VM -VM $vm -Verbose
		}
		'stop' {
			if($param1 -ieq 'force'){Stop-VM -VM $vm -Verbose -Force}
			else {Stop-VM -VM $vm -Verbose}
		}
		'start' {Start-VM -VM $vm -Verbose}
		'save' {Stop-VM -VM $vm -Save -Verbose}
		'migrate' {
			if(! $vm.IsClustered) {
				throw 'VM $($vm.Name) is not clustered. Aborting'
			}
			if(!(get-module -Name FailoverClusters)) {Import-Module FailoverClusters}
			$groups = get-clustergroup | where {$_.GroupType -eq 'VirtualMachine'}
			$res=$null
			foreach($g in $groups) {
				$VMGuid = ($g | Get-ClusterResource | Get-ClusterParameter | where {$_.Name -ieq 'VMID'})[0].Value
				if($VMGuid -eq $vm.Id.ToString()) {
					if($param1 -ieq 'best') {$res = Move-ClusterVirtualMachineRole  -InputObject $g -Verbose}
					else {$res = Move-ClusterVirtualMachineRole  -InputObject $g -Node $param1 -Verbose}
				}
			}
			if(! $res) {throw "VM $($vm.name) not found in cluster resources. Aborting."}
			if ($error.Count -ne 0)
			{
				throw ([string]::Format("Migration was not successfull. Group state {0} and owner {1}. Error: {2}", $res.State, $res.OwnerNode.NodeName, $error[0]))
			}
		}
		'pause' {Suspend-VM -VM $vm -Verbose}
		'resume' {Resume-VM -VM $vm -Verbose}
		'turnoff' {Stop-VM -VM $vm -TurnOff -Verbose}
		'checkpoint' {Checkpoint-VM -VM $vm -SnapshotName $param1 -Verbose}
		'removecheckpoint' {Remove-VMSnapshot -VM $vm -Name $param1 -Verbose}
		'restorecheckpoint' {Restore-VMSnapshot -VM $vm -Name $param1 -Verbose}
		'listcheckpoints' {
			$snapshots = Get-VMSnapshot -VM $vm -Verbose
			$snapshots | fl *
		 }
		default {Write-Host 'Unknown Action'}
	}
	#return the status if we were not migrating
	if($op -ine 'migrate') {$vm = Get-VM -Id $VMId; $vm | fl *;}
	else {$res | fl *}
}
catch {
	Log-Event $FAILURE_EVENT_ID $EVENT_TYPE_WARNING ("Main " + $($Error[0].Exception)) $TRACE_WARNING	
	write-Verbose $("TRAPPED: " + $_.Exception.GetType().FullName); 
	Write-Verbose $("TRAPPED: " + $_.Exception.Message); 
	#relaunch the exception 
	throw ($_.Exception.Message)
}