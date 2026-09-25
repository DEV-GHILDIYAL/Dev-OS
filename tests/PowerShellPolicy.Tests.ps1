$ErrorActionPreference = 'Stop'
$path = Join-Path (Split-Path $PSScriptRoot -Parent) 'virtualization\DevOS.HyperV\Scripts\HyperV.ps1'
$tokens=$null; $errors=$null
$ast = [Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors)
if ($errors.Count) { throw 'Backend PowerShell syntax failed.' }
# Load the actual production policy functions, without executing host operations.
foreach ($function in $ast.FindAll({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst]},$false)) {
    . ([scriptblock]::Create($function.Extent.Text))
}
$passed=0
function Test([string]$testName,[scriptblock]$body) { & $body; $script:passed++; Write-Output "PASS $testName" }
function Assert([bool]$condition) { if (!$condition) { throw 'Assertion failed' } }
function Reject([scriptblock]$body,[string]$expected) {
    $script:failure='OPERATION_FAILED'
    $caught=$false
    try { & $body | Out-Null } catch { $caught=$true }
    Assert ($caught -and $script:failure -eq $expected)
}
Test 'host edition check rejects Home variants' {
    Assert (UnsupportedHostEdition 'CoreSingleLanguage')
    Assert (UnsupportedHostEdition 'Core')
    Assert (!(UnsupportedHostEdition 'Professional'))
    Assert (!(UnsupportedHostEdition 'Enterprise'))
}
$name='DevOS-Phase1'
$id=[guid]::NewGuid()
$script:fixture=[pscustomobject]@{ VmId=$id.ToString(); Stage='Complete'; Marker=('DevOS:'+ [guid]::NewGuid().ToString('N')) }
$script:vm=[pscustomobject]@{ Id=$id; Name=$name; Notes=$fixture.Marker }
function ReadRegistration { return $script:fixture }
function Get-VM { param($Id) if ($Id -eq $script:vm.Id) { return $script:vm } }
Test 'production ownership accepts registration' { Assert ((GetOwnedVm).Id -eq $id) }
Test 'production ownership rejects foreign ID' {
    $original=$fixture.VmId; $fixture.VmId=[guid]::NewGuid().ToString()
    Reject { GetOwnedVm } 'REGISTERED_VM_MISSING'; $fixture.VmId=$original
}
Test 'production ownership rejects modified marker' {
    $original=$vm.Notes; $vm.Notes='foreign'
    Reject { GetOwnedVm } 'OWNERSHIP_MISMATCH'; $vm.Notes=$original
}
Test 'production ownership rejects partial creation' {
    $fixture.Stage='Creating'; Reject { GetOwnedVm } 'REGISTRATION_INCOMPLETE'; $fixture.Stage='Complete'
}
Test 'production ownership rejects malformed ID' {
    $original=$fixture.VmId; $fixture.VmId='not-a-guid'
    Reject { GetOwnedVm } 'INVALID_REGISTRATION'; $fixture.VmId=$original
}
Test 'production media verification rejects missing image' {
    $iso=Join-Path $env:TEMP ([guid]::NewGuid().ToString('N')+'.iso')
    $mediaRecord=$iso+'.json'
    Reject { VerifyMedia } 'ISO_MISSING_OR_UNVERIFIED'
}
Test 'production integration ID handles qualified instance names' {
    $component='84eaae65-2f2e-45f5-9bb5-0e857dc8eb47'
    Assert ((IntegrationId ([pscustomobject]@{Id="Microsoft:$id\$component"})) -eq $component)
    Assert ((IntegrationId ([pscustomobject]@{Id=$component.ToUpperInvariant()})) -eq $component)
}
$disk=Join-Path $env:TEMP 'DevOS-test-nonexistent.vhdx'
$iso=Join-Path $env:TEMP 'DevOS-test-nonexistent.iso'
$script:memory=[pscustomobject]@{Startup=4GB; DynamicMemoryEnabled=$false}
$script:firmware=[pscustomobject]@{SecureBoot='On';SecureBootTemplate='MicrosoftUEFICertificateAuthority'}
$script:drive=[pscustomobject]@{Path=$disk}
$script:integration=@('0e0b6031-5213-4934-818b-38d90ced39db','84eaae65-2f2e-45f5-9bb5-0e857dc8eb47','2497f4de-e9fa-4204-80e4-4b75c46419c0') | ForEach-Object { [pscustomobject]@{Id="Microsoft:$id\$_";Enabled=$true} }
function Get-VMMemory { param($VM) return $script:memory }
function Get-VMProcessor { param($VM) return [pscustomobject]@{Count=2} }
function Get-VMFirmware { param($VM) return $script:firmware }
function Get-VMHardDiskDrive { param($VM) return $script:drive }
function Get-VMNetworkAdapter { param($VM) return [pscustomobject]@{SwitchId=[guid]::Empty} }
function Get-VMSnapshot { param($VM) }
function Get-VHD { param($Path) return [pscustomobject]@{VhdType='Fixed';Size=48GB;ParentPath=$null} }
function Get-VMIntegrationService { param($VM) return $script:integration }
function Get-VMDvdDrive { param($VM) return [pscustomobject]@{Path=$iso} }
$configVm=[pscustomobject]@{Generation=2;AutomaticStartAction='Nothing';AutomaticStopAction='ShutDown';CheckpointType='Disabled';AutomaticCheckpointsEnabled=$false}
Test 'production configuration accepts approved fixture' { CheckConfiguration $configVm }
Test 'production configuration rejects dynamic RAM' {
    $memory.DynamicMemoryEnabled=$true; Reject { CheckConfiguration $configVm } 'CONFIGURATION_DRIFT'; $memory.DynamicMemoryEnabled=$false
}
Test 'production configuration rejects foreign disk' {
    $drive.Path='C:\foreign.vhdx'; Reject { CheckConfiguration $configVm } 'CONFIGURATION_DRIFT'; $drive.Path=$disk
}
Test 'production configuration rejects disabled Secure Boot' {
    $firmware.SecureBoot='Off'; Reject { CheckConfiguration $configVm } 'CONFIGURATION_DRIFT'; $firmware.SecureBoot='On'
}
Test 'production configuration requires shutdown integration' {
    $integration[0].Enabled=$false; Reject { CheckConfiguration $configVm } 'INTEGRATION_CONFIGURATION_DRIFT'; $integration[0].Enabled=$true
}
Write-Output "$passed PASS, 0 FAIL (production PowerShell policy)"
