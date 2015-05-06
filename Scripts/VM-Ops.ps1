param([string] $VMId,
      [String] $op,
      [string] $param1)


$vm = get-VM -Id $VMId
if (!$vm) {
    Write-Host 'Not Found'
    Throw 'Not Found' #so the task terminates in error
}

switch ($op) {
'stop' {}
'start' {}
'save' {}
'migrate' {}

}