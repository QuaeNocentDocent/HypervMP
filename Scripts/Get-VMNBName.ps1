param($vmName)

#MOM API
$oAPI = New-Object -ComObject "MOM.ScriptAPI"

$NBName = ($vmName.Split('.'))[0]
$oBag = $oAPI.CreatePropertyBag()
$oBag.AddValue('NetBIOSName', $NBName)
$obag