'===================================================================================
' AUTHOR:         	Tao Yang
' Script Name:    	ClusterNodesStatusProbe.vbs
' DATE:           	11/07/2012
' Version:        	1.0
' COMMENT:			- Script Check the status of cluster nodes
'===================================================================================
'ON ERROR RESUME NEXT
strComputer = Wscript.Arguments(0)
VMsOnWrongHost = Wscript.Arguments(1)
Set oAPI = CreateObject("MOM.ScriptAPI")
Set oBag = oAPI.CreatePropertyBag()
Set objWMICluster = GetObject("winmgmts:\\" & strComputer & "\root\MSCluster")
bHealthyCluster = TRUE
WMIQuery = "select Name,State from MSCluster_Node"
Set colClusterNodes = objWMICluster.ExecQuery (WMIQuery)

For Each objClusterNode in colClusterNodes
	IF objClusterNode.State <> 0 THEN
		bHealthyCluster = FALSE
	END IF
Next
'Overall result
Set oBag = oAPI.CreatePropertyBag()
oBag.AddValue "ClusterName", strComputer
oBag.AddValue "VMsOnWrongHost", VMsOnWrongHost
oBag.AddValue "Healthy", bHealthyCluster
oAPI.Return(oBag)
