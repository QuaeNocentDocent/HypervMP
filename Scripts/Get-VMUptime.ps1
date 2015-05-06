#TO SHOW VERBOSE MESSAGES SET $VerbosePreference="continue"
#SET ErrorLevel to 5 so show discovery info

#*************************************************************************
# Script Name - Discover-PrimaryReplicaVM.ps1
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
	[string]$MGGuid,
	[string]$VMGuid)


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

Function NullIsZero
{
	param($value)
	if(! $value) {return 0}
	return $value
}

Function Process-VM
{
	param($vm)
	$lastCheck = [xml] (Get-Content -Path "$($vm.Path)\$MGGuid-UpTimeCheck.xml" -ErrorAction SilentlyContinue)
	$vmUpTime = NullIsZero $vm.Uptime.TotalHours
	if(! $lastCheck) {
		$lastCheck = "<LastUptimeCheck><Uptime>$vmUpTime</Uptime><Check>$timeNow</Check></LastUptimeCheck>"
		Log-Event $START_EVENT_ID $EVENT_TYPE_INFORMATION ("No previous uptime data exists for $($vm.Name)") $TRACE_INFO
		$lastCheck | Out-File -FilePath "$($vm.Path)\$MGGuid-UpTimeCheck.xml" -Force
		return;
	}
	$lastTotalHours = [double] ($lastCheck.LastUptimeCheck.Uptime)
	$lastDateCheck = [DateTime] ($lastCheck.LastUptimeCheck.Check)
			
	$uptimeInperiod = $vm.Uptime.TotalHours - $lastTotalHours
	if($uptimeInPeriod -le 0) {$uptimeInPeriod = $vm.Uptime.TotalHours}
	$elapsedInPeriod = ($timeNow - $lastDateCheck).TotalHours
	$percUptime = [math]::Round($uptimeInperiod/$elapsedInPeriod * 100,2)
	if($percUptime -gt 100){$percUptime=100.00}
	$lastCheck = "<LastUptimeCheck><Uptime>$vmUpTime</Uptime><Check>$TimeNow</Check></LastUptimeCheck>"
	$lastCheck | Out-File -FilePath "$($vm.Path)\$MGGuid-UpTimeCheck.xml" -Force

	$bag = $g_api.CreatePropertyBag()
	$bag.AddValue('VMId',$vm.VMId.ToString())
	$bag.AddValue('PercUptime', (NullIsZero $percUptime))
	$bag.AddValue('TotalUptime',(NullIsZero $vm.Uptime.TotalHours))
	$bag.AddValue('UptimeInPeriod',(NullIsZero $uptimeInperiod))
	#now return the disk data if we have any
	$bag
	Log-Event $START_EVENT_ID $EVENT_TYPE_INFO ("$($vm.Name) has been processed, uptime perc is $percUptime") $TRACE_VERBOSE
}
#Start by setting up API object.
	$P_TraceLevel = $TRACE_VERBOSE
	$g_Api = New-Object -comObject 'MOM.ScriptAPI'
	$g_RegistryStatePath = "HKLM\" + $g_API.GetScriptStateKeyPath($SCRIPT_NAME) + "\$MGGuid"

	$dtStart = Get-Date
	$P_TraceLevel = $traceLevel
	Log-Params $MyInvocation

try
{
	if (!(get-Module -Name Hyper-v)) {Import-Module Hyper-v}


	if (!(get-command -Module Hyper-V -Name Get-VM -ErrorAction SilentlyContinue)) {
		Log-Event $START_EVENT_ID $EVENT_TYPE_WARNING ("Get-VM Commandlet doesn't exist.") $TRACE_WARNING
		Exit 1;
	}

	if ($VMGuid -ine 'ignore') {	#here we're in atask targeted at a specific VM
		$vm = Get-VM | where {$_.VMId -ieq $VMGuid}
		if($vm) {Process-VM $vm}
		exit;
	}

	#$vms = @(gwmi Msvm_ComputerSystem -namespace "root\virtualization\v2" | where {$_.ReplicationMode -ne 0 -and $_.ReplicationMode -ne $null})
	$timeNow = [DateTime]::Now
	$VMs=Get-VM
	foreach($vm in $VMs) {
		try {
			Process-VM $vm
		}
		Catch [Exception] {
			Log-Event $START_EVENT_ID $EVENT_TYPE_WARNING ("$($vm.Name) error getting Uptime info $($Error[0].Exception)") $TRACE_WARNING
		}
	}

	Log-Event $STOP_EVENT_ID $EVENT_TYPE_SUCCESS ("has completed successfully in " + ((Get-Date)- ($dtstart)).TotalSeconds + " seconds.") $TRACE_INFO
}
Catch [Exception] {
	Log-Event $FAILURE_EVENT_ID $EVENT_TYPE_WARNING ("Main " + $($Error[0].Exception)) $TRACE_WARNING	
	write-Verbose $("TRAPPED: " + $_.Exception.GetType().FullName); 
	Write-Verbose $("TRAPPED: " + $_.Exception.Message); 
}
