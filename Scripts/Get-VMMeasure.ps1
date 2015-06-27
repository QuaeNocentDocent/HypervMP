#TO SHOW VERBOSE MESSAGES SET $VerbosePreference="continue"
#SET ErrorLevel to 5 so show discovery info

#*************************************************************************
# Script Name - Get-VMMeasure.ps1
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
	[string]$VMGuid,
	[int]$ResetDays)

	[Threading.Thread]::CurrentThread.CurrentCulture = "en-US"        
	[Threading.Thread]::CurrentThread.CurrentUICulture = "en-US"
	
#Constants used for event logging
$SCRIPT_NAME			= "Get-VMMeasure.ps1"
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

Function NullZero
{
	param($value)
	if(! $value) {return 0}
	return $value
}

Function Process-VM
{
	param($measure)
	$bag = $g_api.CreatePropertyBag()
	$bag.AddValue('VMId',$measure.VMId.ToString())
	$bag.AddValue('Type','VM')
	$bag.AddValue('AvgCPU', (NullZero $measure.AverageProcessorUsage))
	$bag.AddValue('AvgMemory',(NullZero $measure.AverageMemoryUsage))
	$bag.AddValue('MaxMemory',(NullZero $measure.MaximumMemoryUsage))
	$bag.AddValue('DiskAllocation',(NullZero $measure.TotalDiskAllocation))
	$bag.AddValue('NormalizedIOPS',(NullZero $measure.AggregatedAverageNormalizedIOPS))
	$bag.AddValue('AvgDiskLatency',(NullZero $measure.AggregatedAverageLatency))
	#the following metrics are an absolute value so if collected they need to be collected in delta
	$bag.AddValue('DiskDataRead',(NullZero $measure.AggregatedDiskDataRead))
	$bag.AddValue('DiskDataWritten',(NullZero $measure.AggregatedDiskDataWritten))

	#try to transform in Avg, but sometime the metering time is null
	if($measure.MeteringDuration) {
		$DataPerSecSignificant=1
		$DiskDataReadPerSec = (NullZero $measure.AggregatedDiskDataRead) / $measure.MeteringDuration.TotalSeconds
		$DiskDataWrittendPerSec = (NullZero $measure.AggregatedDiskDataWritten) / $measure.MeteringDuration.TotalSeconds
	}
	else {
		$DataPerSecSignificant=0
		$DiskDataReadPerSec = 0
		$DiskDataWrittenPerSec = 0
	}
	$bag.AddValue('DiskDataWrittenPerSec',(NullZero $DiskDataWrittendPerSec))
	$bag.AddValue('DiskDataReadPerSec',(NullZero $DiskDataReadPerSec))
	$bag.AddValue('DiskDataPerSecSignificant',$DataPerSecSignificant)

	#now return aggregated Network Data if any
	$outboundTraffic = ($measure.NetworkMeteredTrafficReport | where {$_.Direction -ieq 'Outbound'} | Measure-Object -Property TotalTraffic -Sum).Sum
	$inboundTraffic = ($measure.NetworkMeteredTrafficReport | where {$_.Direction -ieq 'Inbound'} | Measure-Object -Property TotalTraffic -Sum).Sum
	$bag.AddValue("OutboundTraffic",(NullZero $outboundTraffic))
	$bag.AddValue("InboundTraffic",(NullZero $inboundTraffic))
	#try to transform in Avg, but sometime the metering time is null
	if($measure.MeteringDuration) {
		$DataPerSecSignificant=1
		$OutboundPerSec = (NullZero $outboundTraffic) / $measure.MeteringDuration.TotalSeconds
		$InboundPerSec = (NullZero $inboundTraffic) / $measure.MeteringDuration.TotalSeconds
	}
	else {
		Log-Event $START_EVENT_ID $EVENT_TYPE_INFO ("$($measure.VMName) doesn't report Metering Duration. Some Perf counters will be missing.") $TRACE_VERBOSE
		$DataPerSecSignificant=0
		$OutboundPerSec = 0
		$InboundPerSec = 0
	}
	$bag.AddValue("OutboundTrafficPerSec",(NullZero $OutboundPerSec))
	$bag.AddValue("InboundTrafficPerSec",(NullZero $InboundPerSec))
	$bag.AddValue("TrafficPerSecSignificant",$DataPerSecSignificant)

	#now we can return the data
	$bag
	
	#now return the disk data if we have any

	foreach($disk in $measure.HardDiskMetrics) {
		$bag = $g_api.CreatePropertyBag()
		
		$diskId = $disk.VirtualHardDisk.Id
		$bag.AddValue('VMId',$measure.VMId.ToString())
		$bag.AddValue('DiskId',$diskId)
		$bag.AddValue('Type','Disk')
		$bag.AddValue("NormalizedIOPS",(NullZero $disk.AverageNormalizedIOPS))
		$bag.AddValue("AvgDiskLatency",(NullZero $disk.AverageLatency))
		$bag.AddValue("DiskDataRead",(NullZero $disk.DataRead))
		$bag.AddValue("DiskDataWritten",(NullZero $disk.DataWritten))
		#try to transform in Avg, but sometime the metering time is null
		if($measure.MeteringDuration) {
			$DataPerSecSignificant=1
			$DiskDataReadPerSec = (NullZero $disk.DataRead) / $measure.MeteringDuration.TotalSeconds
			$DiskDataWrittendPerSec = (NullZero $disk.DataWritten) / $measure.MeteringDuration.TotalSeconds
		}
		else {

			$DataPerSecSignificant=0
			$DiskDataReadPerSec = 0
			$DiskDataWrittenPerSec = 0
		}
		$bag.AddValue("DiskDataWrittenPerSec",(NullZero $DiskDataWrittendPerSec))
		$bag.AddValue("DiskDataReadPerSec",(NullZero $DiskDataReadPerSec))
		$bag.AddValue("DiskDataPerSecSignificant",$DataPerSecSignificant)
		$bag
	}
	#end reset the statistics
	#Reset-VMResourceMetering -VMName $measure.VMName
	Log-Event $START_EVENT_ID $EVENT_TYPE_INFO ("$($measure.VMName) has been processed") $TRACE_VERBOSE
}
#Start by setting up API object.
	$P_TraceLevel = $TRACE_VERBOSE
	$g_Api = New-Object -comObject 'MOM.ScriptAPI'
	$g_RegistryStatePath = "HKLM:\" + $g_API.GetScriptStateKeyPath($SCRIPT_NAME)

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
		$measure = Get-VM | where {$_.VMId -ieq $VMGuid -and $_.ResourceMeteringEnabled -eq $true} | Measure-VM
		if($measure) {Process-VM $measure}
		exit;
	}

	#$vms = @(gwmi Msvm_ComputerSystem -namespace "root\virtualization\v2" | where {$_.ReplicationMode -ne 0 -and $_.ReplicationMode -ne $null})

	$measures=Get-VM | where {$_.ResourceMeteringEnabled -eq $true} | Measure-VM
	foreach($measure in $measures) {
		try {
			Process-VM $measure
		}
		Catch [Exception] {
			Log-Event $START_EVENT_ID $EVENT_TYPE_WARNING ("$($measure.VMName) error getting performace info $($Error[0].Exception)") $TRACE_WARNING
		}
	}

	#check if we need to reset measures
	if($ResetDays -gt 0) {
		$regVault = Get-Item $g_RegistryStatePath
		if($regVault.GetValueNames() -contains 'LastReset') {
			$lastReset = [DateTime] (Get-ItemProperty -Path $g_RegistryStatePath -Name LastReset).LastReset
			if(([DateTime]::Now-$lastReset).TotalDays -gt $ResetDays) {
				Get-VM | where {$_.ResourceMeteringEnabled -eq $true} | Reset-VMResourceMetering
				Set-ItemProperty -Path $g_RegistryStatePath -Name LastReset -Value ([DateTime]::Now)
			}
		}
		else {Set-ItemProperty -Path $g_RegistryStatePath -Name LastReset -Value ([DateTime]::Now)}
	}
	Log-Event $STOP_EVENT_ID $EVENT_TYPE_SUCCESS ("has completed successfully in " + ((Get-Date)- ($dtstart)).TotalSeconds + " seconds.") $TRACE_INFO
}
Catch [Exception] {
	Log-Event $FAILURE_EVENT_ID $EVENT_TYPE_WARNING ("Main " + $($Error[0].Exception)) $TRACE_WARNING	
	write-Verbose $("TRAPPED: " + $_.Exception.GetType().FullName); 
	Write-Verbose $("TRAPPED: " + $_.Exception.Message); 
}
