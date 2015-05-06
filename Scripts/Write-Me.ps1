param([string]$VMName=$(throw 'must have a value'))

	[Threading.Thread]::CurrentThread.CurrentCulture = "en-US"        
	[Threading.Thread]::CurrentThread.CurrentUICulture = "en-US"

	$g_Api = New-Object -comObject 'MOM.ScriptAPI'
	$HVHost= gwmi -Class win32_computersystem
			$g_API.LogScriptEvent('Write-Me.ps1',1022,4, "I'm $VMName and I'm being monitored by $($hvhost.name) in domain $($hvhost.domain)")