$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$root = Join-Path $env:ProgramData 'DevOS'
$registrationPath = Join-Path $root 'registration.json'
$vmRoot = Join-Path $root 'vm'
$disk = Join-Path $vmRoot 'devos.vhdx'
$mediaRoot = Join-Path $root 'media'
$isoName = 'debian-13.7.0-amd64-netinst.iso'
$iso = Join-Path $mediaRoot $isoName
$mediaRecord = Join-Path $mediaRoot 'verified.json'
$name = 'DevOS-Phase1'
$failure = 'OPERATION_FAILED'

function Fail([string] $code) { $script:failure = $code; throw $code }
function UnsupportedHostEdition([string] $edition) {
    return $edition -match '^Core'
}
function CheckPath([string] $path) {
    $current = [IO.Path]::GetFullPath($path)
    while ($current) {
        if (Test-Path -LiteralPath $current) {
            if ((Get-Item -LiteralPath $current -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { Fail 'REPARSE_POINT_REJECTED' }
        }
        $current = [IO.Path]::GetDirectoryName($current)
    }
}
function ReadRegistration {
    CheckPath $registrationPath
    if (Test-Path -LiteralPath $registrationPath) { return Get-Content -LiteralPath $registrationPath -Raw | ConvertFrom-Json }
    return $null
}
function SaveRegistration($value) {
    $temporary = Join-Path $root 'registration.pending'
    CheckPath $temporary
    $value | ConvertTo-Json -Compress | Set-Content -LiteralPath $temporary -Encoding UTF8
    Move-Item -LiteralPath $temporary -Destination $registrationPath -Force
}
function GetOwnedVm {
    $r = ReadRegistration
    if (!$r -or !$r.VmId -or $r.Stage -ne 'Complete') { Fail 'REGISTRATION_INCOMPLETE' }
    $id = [guid]::Empty
    if (![guid]::TryParse($r.VmId, [ref]$id) -or $id -eq [guid]::Empty) { Fail 'INVALID_REGISTRATION' }
    $v = Get-VM -Id $id -ErrorAction SilentlyContinue
    if (!$v) { Fail 'REGISTERED_VM_MISSING' }
    if ($v.Notes -cne $r.Marker -or $r.Marker -notmatch '^DevOS:[a-f0-9]{32}$' -or $v.Name -cne $name) { Fail 'OWNERSHIP_MISMATCH' }
    return $v
}
function IntegrationId($service) {
    # Hyper-V may return a qualified Microsoft:<VM-ID>\<component-ID> instance identifier.
    return ($service.Id.ToString() -split '\\')[-1].ToLowerInvariant()
}
function CheckConfiguration($v) {
    CheckPath $disk
    $memory = Get-VMMemory -VM $v
    $cpu = Get-VMProcessor -VM $v
    $firmware = Get-VMFirmware -VM $v
    $drives = @(Get-VMHardDiskDrive -VM $v)
    $nics = @(Get-VMNetworkAdapter -VM $v)
    if ($v.Generation -ne 2 -or $cpu.Count -ne 2 -or $memory.Startup -ne 4GB -or $memory.DynamicMemoryEnabled -or
        $v.AutomaticStartAction -ne 'Nothing' -or $v.AutomaticStopAction -ne 'ShutDown' -or
        $v.CheckpointType -ne 'Disabled' -or $v.AutomaticCheckpointsEnabled -or
        $firmware.SecureBoot -ne 'On' -or $firmware.SecureBootTemplate -ne 'MicrosoftUEFICertificateAuthority' -or
        $drives.Count -ne 1 -or $drives[0].Path -ine $disk -or $nics.Count -ne 1 -or
        @(Get-VMSnapshot -VM $v).Count -ne 0) { Fail 'CONFIGURATION_DRIFT' }
    $vhd = Get-VHD -Path $disk
    if ($vhd.VhdType -ne 'Fixed' -or $vhd.Size -ne 48GB -or $vhd.ParentPath) { Fail 'DISK_CONFIGURATION_DRIFT' }
    $enabled = @(Get-VMIntegrationService -VM $v | Where-Object Enabled)
    $allowed = @('0e0b6031-5213-4934-818b-38d90ced39db','84eaae65-2f2e-45f5-9bb5-0e857dc8eb47','2497f4de-e9fa-4204-80e4-4b75c46419c0')
    if ($enabled.Count -ne $allowed.Count) { Fail 'INTEGRATION_CONFIGURATION_DRIFT' }
    foreach ($service in $enabled) { if ((IntegrationId $service) -notin $allowed) { Fail 'INTEGRATION_CONFIGURATION_DRIFT' } }
    $dvds = @(Get-VMDvdDrive -VM $v)
    if ($dvds.Count -gt 1) { Fail 'UNEXPECTED_MEDIA' }
    if ($dvds.Count -eq 1 -and $dvds[0].Path -and $dvds[0].Path -ine $iso) { Fail 'UNEXPECTED_MEDIA' }
    if ($nics[0].SwitchId -and $nics[0].SwitchId -ne [guid]::Empty -and
        $nics[0].SwitchId -ne [guid]'c08cb7b8-9b3c-408e-8e30-5e16a3aeb444') { Fail 'UNEXPECTED_NETWORK' }
}
function VerifyMedia {
    CheckPath $iso
    CheckPath $mediaRecord
    if (!(Test-Path -LiteralPath $iso) -or !(Test-Path -LiteralPath $mediaRecord)) { Fail 'ISO_MISSING_OR_UNVERIFIED' }
    $record = Get-Content -LiteralPath $mediaRecord -Raw | ConvertFrom-Json
    if ($record.Filename -cne $isoName -or $record.DebianVersion -ne '13.7.0' -or
        $record.Signer -ne 'DF9B9C49EAA9298432589D76DA87E80D6294BE9B' -or
        (Get-FileHash -LiteralPath $iso -Algorithm SHA256).Hash -ine $record.SHA256) { Fail 'ISO_CHECKSUM_MISMATCH' }
}
function PrepareMedia {
    $gpg = Join-Path $env:ProgramFiles 'Git\usr\bin\gpg.exe'
    CheckPath $gpg
    if (!(Test-Path -LiteralPath $gpg)) { Fail 'TRUSTED_GPG_MISSING' }
    New-Item -ItemType Directory -Path $mediaRoot -Force | Out-Null
    $gpgHome = Join-Path $mediaRoot 'gnupg'
    New-Item -ItemType Directory -Path $gpgHome -Force | Out-Null
    $source = 'https://cdimage.debian.org/debian-cd/13.7.0/amd64/iso-cd/'
    $sums = Join-Path $mediaRoot 'SHA256SUMS'
    $signature = Join-Path $mediaRoot 'SHA256SUMS.sign'
    $key = Join-Path $mediaRoot 'debian-cd.asc'
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -UseBasicParsing ($source + 'SHA256SUMS') -OutFile $sums -TimeoutSec 60
    Invoke-WebRequest -UseBasicParsing ($source + 'SHA256SUMS.sign') -OutFile $signature -TimeoutSec 60
    Invoke-WebRequest -UseBasicParsing 'https://keyring.debian.org/pks/lookup?op=get&search=0xDA87E80D6294BE9B' -OutFile $key -TimeoutSec 60
    $ErrorActionPreference = 'Continue'
    & $gpg --batch --homedir $gpgHome --import $key 2>$null | Out-Null
    $importExit = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'
    if ($importExit -ne 0) { Fail 'SIGNING_KEY_IMPORT_FAILED' }
    $ErrorActionPreference = 'Continue'
    $status = & $gpg --batch --homedir $gpgHome --status-fd 1 --verify $signature $sums 2>$null
    $verifyExit = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'
    if ($verifyExit -ne 0 -or !($status -match '^\[GNUPG:\] VALIDSIG DF9B9C49EAA9298432589D76DA87E80D6294BE9B ')) { Fail 'DEBIAN_SIGNATURE_INVALID' }
    $line = @(Get-Content -LiteralPath $sums | Where-Object { $_ -match ('^[0-9a-fA-F]{64}  ' + [regex]::Escape($isoName) + '$') })
    if ($line.Count -ne 1) { Fail 'ISO_NOT_IN_SIGNED_MANIFEST' }
    $digest = $line[0].Substring(0,64)
    if (!(Test-Path -LiteralPath $iso)) { Invoke-WebRequest -UseBasicParsing ($source + $isoName) -OutFile $iso -TimeoutSec 1200 }
    if ((Get-FileHash -LiteralPath $iso -Algorithm SHA256).Hash -ine $digest) { Fail 'ISO_CHECKSUM_MISMATCH' }
    @{ Filename=$isoName; DebianVersion='13.7.0'; SHA256=$digest; Source=($source+$isoName);
       Signer='DF9B9C49EAA9298432589D76DA87E80D6294BE9B'; VerifiedAt=[DateTimeOffset]::UtcNow.ToString('o') } |
       ConvertTo-Json | Set-Content -LiteralPath $mediaRecord -Encoding UTF8
}
function Inspect {
    $os = Get-CimInstance Win32_OperatingSystem
    $machine = Get-CimInstance Win32_ComputerSystem
    $drive = [IO.DriveInfo]::new([IO.Path]::GetPathRoot($root))
    $module = [bool](Get-Module -ListAvailable Hyper-V)
    $service = Get-Service vmms -ErrorAction SilentlyContinue
    $feature = 'Unknown (administrator query required)'
    if (([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        $feature = (Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All).State.ToString()
    }
    $o = [ordered]@{ Windows=$os.Caption; Feature=$feature; Module=$module; Vmms='Missing';
        HypervisorPresent=[bool]$machine.HypervisorPresent; AvailableMemoryMiB=[long]($os.FreePhysicalMemory/1024);
        AvailableStorageGiB=[long]($drive.AvailableFreeSpace/1GB); Registered=$false; Exists=$false; Owned=$false;
        Compliant=$false; Power='Unknown'; VmId=$null; Network='Unknown'; Code='OK'; ObservedAt=[DateTimeOffset]::UtcNow.ToString('o') }
    if ($service) { $o.Vmms=$service.Status.ToString() }
    $r = ReadRegistration
    $o.Registered = [bool]$r
    $edition = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').EditionID
    if (UnsupportedHostEdition $edition) { $o.Code='WINDOWS_EDITION_UNSUPPORTED'; return $o }
    if ((Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') -and !$module) {
        $o.Feature = 'Reboot pending; management components not yet available'
    }
    if (!$module) { $o.Code='HYPERV_MODULE_MISSING'; return $o }
    if (!$service -or $service.Status -ne 'Running') { $o.Code='VMMS_UNAVAILABLE'; return $o }
    try {
        if (!$r) {
            $existing = @(Get-VM -ErrorAction Stop | Where-Object Name -eq $name)
            $o.Exists = $existing.Count -gt 0
            if ($o.Exists) { $o.Code='UNREGISTERED_VM_CONFLICT' }
            return $o
        }
        $v = GetOwnedVm
        $o.Exists=$true; $o.Owned=$true; $o.Power=$v.State.ToString(); $o.VmId=$v.Id.ToString()
        CheckConfiguration $v
        $o.Compliant=$true
        $nic = Get-VMNetworkAdapter -VM $v
        $o.Network = 'Disconnected'
        if ($nic.SwitchId -and $nic.SwitchId -ne [guid]::Empty) { $o.Network = 'Installation Network / Ordinary NAT' }
    } catch {
        if ($script:failure -eq 'OPERATION_FAILED') { $o.Code='HYPERV_QUERY_DENIED_OR_FAILED' } else { $o.Code=$script:failure }
    }
    return $o
}

try {
    CheckPath $root
    if ($operation -eq 'Inspect') {
        @{Success=$true; Code='OK'; Observation=(Inspect)} | ConvertTo-Json -Depth 5 -Compress
        return
    }
    $owner = (Get-ItemProperty 'HKLM:\SOFTWARE\DevOS').OwnerSid
    if ($owner -ne [Security.Principal.WindowsIdentity]::GetCurrent().User.Value) { Fail 'OWNER_IDENTITY_MISMATCH' }
    $edition = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').EditionID
    if (UnsupportedHostEdition $edition) { Fail 'WINDOWS_EDITION_UNSUPPORTED' }
    if ($operation -eq 'PrepareMedia') { PrepareMedia }
    else {
        if (!(Get-Module -ListAvailable Hyper-V)) { Fail 'HYPERV_MODULE_MISSING' }
        if ((Get-Service vmms -ErrorAction SilentlyContinue).Status -ne 'Running') { Fail 'VMMS_UNAVAILABLE' }
        if ($operation -eq 'Create') {
            if (ReadRegistration) { Fail 'REGISTRATION_ALREADY_EXISTS' }
            if (@(Get-VM | Where-Object Name -eq $name).Count) { Fail 'VM_ALREADY_EXISTS' }
            if (Test-Path -LiteralPath $disk) { Fail 'VHDX_ALREADY_EXISTS' }
            $drive = [IO.DriveInfo]::new([IO.Path]::GetPathRoot($root))
            if ($drive.AvailableFreeSpace -lt 74GB) { Fail 'INSUFFICIENT_DISK_SPACE' }
            if ((Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory -lt (5GB/1KB)) { Fail 'INSUFFICIENT_FREE_RAM' }
            VerifyMedia
            $r = [ordered]@{ VmId=$null; Marker=('DevOS:'+[guid]::NewGuid().ToString('N')); Stage='Creating' }
            SaveRegistration $r
            New-Item -ItemType Directory -Path $vmRoot -Force | Out-Null
            CheckPath $vmRoot
            New-VHD -Path $disk -SizeBytes 48GB -Fixed | Out-Null
            $v = New-VM -Name $name -Generation 2 -MemoryStartupBytes 4GB -VHDPath $disk -Path $vmRoot
            $r.VmId=$v.Id.ToString(); SaveRegistration $r
            Set-VM -VM $v -Notes $r.Marker -AutomaticStartAction Nothing -AutomaticStopAction ShutDown -CheckpointType Disabled -AutomaticCheckpointsEnabled $false
            Set-VMProcessor -VM $v -Count 2
            Set-VMMemory -VM $v -DynamicMemoryEnabled $false -StartupBytes 4GB
            Set-VMFirmware -VM $v -EnableSecureBoot On -SecureBootTemplate MicrosoftUEFICertificateAuthority
            Get-VMIntegrationService -VM $v | Disable-VMIntegrationService
            Get-VMIntegrationService -VM $v | Where-Object { (IntegrationId $_) -in @('0e0b6031-5213-4934-818b-38d90ced39db','84eaae65-2f2e-45f5-9bb5-0e857dc8eb47','2497f4de-e9fa-4204-80e4-4b75c46419c0') } | Enable-VMIntegrationService
            Get-VMNetworkAdapter -VM $v | Disconnect-VMNetworkAdapter
            $dvd = Add-VMDvdDrive -VM $v -Path $iso -Passthru
            Set-VMFirmware -VM $v -FirstBootDevice $dvd
            $account = ([Security.Principal.SecurityIdentifier]$owner).Translate([Security.Principal.NTAccount]).Value
            Grant-VMConnectAccess -VMName $name -UserName $account
            CheckConfiguration (Get-VM -Id $v.Id)
            $r.Stage='Complete'; SaveRegistration $r
        } else {
            $v = GetOwnedVm
            # Shutdown remains available for our VM even if a configuration change is detected.
            if ($operation -ne 'Shutdown') { CheckConfiguration $v }
            switch ($operation) {
                'Start' {
                    if ($v.State -ne 'Off') { Fail 'VM_NOT_OFF' }
                    if ((Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory -lt (5GB/1KB)) { Fail 'INSUFFICIENT_FREE_RAM' }
                    $dvd = Get-VMDvdDrive -VM $v
                    if ($dvd.Path) { VerifyMedia }
                    Start-VM -VM $v | Out-Null
                }
                'Shutdown' {
                    if ($v.State -ne 'Off') {
                        if ($v.State -ne 'Running') { Fail 'VM_STATE_UNSUPPORTED_FOR_SHUTDOWN' }
                        Stop-VM -VM $v -Confirm:$false -AsJob | Wait-Job -Timeout 120 | Out-Null
                        if ((Get-VM -Id $v.Id).State -ne 'Off') { Fail 'SHUTDOWN_TIMEOUT' }
                    }
                }
                'ConnectInstallationNetwork' {
                    $switch = Get-VMSwitch -Id 'c08cb7b8-9b3c-408e-8e30-5e16a3aeb444' -ErrorAction SilentlyContinue
                    if (!$switch) { Fail 'DEFAULT_SWITCH_MISSING' }
                    Get-VMNetworkAdapter -VM $v | Connect-VMNetworkAdapter -SwitchName $switch.Name
                }
                'DisconnectNetwork' { Get-VMNetworkAdapter -VM $v | Disconnect-VMNetworkAdapter }
                'EjectMedia' {
                    if ($v.State -ne 'Off') { Fail 'VM_NOT_OFF' }
                    Get-VMDvdDrive -VM $v | Set-VMDvdDrive -Path $null
                }
                default { Fail 'INVALID_OPERATION' }
            }
        }
    }
    @{Success=$true; Code='OK'; Observation=(Inspect)} | ConvertTo-Json -Depth 5 -Compress
} catch {
    # Output only bounded allowlisted error categories, never raw PowerShell exceptions.
    $edition = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction SilentlyContinue).EditionID
    $code = if (UnsupportedHostEdition $edition) { 'WINDOWS_EDITION_UNSUPPORTED' }
        elseif ([string]::IsNullOrWhiteSpace($script:failure)) { 'OPERATION_FAILED' }
        else { $script:failure }
    @{Success=$false; Code=$code; Observation=$null} | ConvertTo-Json -Compress
}
