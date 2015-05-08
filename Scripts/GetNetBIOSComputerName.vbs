'===================================================================================
' AUTHOR:         	Tao Yang
' Script Name:    	GetNetBIOSCOmputerName.vbs
' DATE:           	07/04/2015
' Version:        	1.0
' COMMENT:			- Retrieve the NetBIOS computer name from FQDN
'===================================================================================
'ON ERROR RESUME NEXT

FQDN = Wscript.Arguments(0)
Set oAPI = CreateObject("MOM.ScriptAPI")
Set oBag = oAPI.CreatePropertyBag()
'Chop FQDN to get NetBIOSName
NetBIOSName = split(FQDN, ".")(0)

'Overall result
Set oBag = oAPI.CreatePropertyBag()
oBag.AddValue "NetBIOSName", NetBIOSName
oAPI.Return(oBag)
