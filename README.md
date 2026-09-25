# DevOS

Phase 1 disposable Windows/Hyper-V prototype. Encryption is not configured. Do not use private data in this VM.

The launcher uses WPF and .NET 10. A short-lived UAC broker handles privileged operations. Debian installation is performed through the basic Hyper-V console. Running means VM power only; guest readiness remains unknown.

## Build

On Windows x64, use the pinned .NET 10.0.401 SDK, or run `scripts/Install-LocalSdk.ps1` to download and verify a local SDK from Microsoft. Then:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts\Build.ps1
```

The script builds `DevOS.sln`, runs the C# test executable and production PowerShell policy tests, then publishes self-contained Windows x64 artifacts. No third-party NuGet packages are required. The local SDK, build output, virtual disks and media are ignored by Git.

## Compatibility And Setup

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts\Check-Compatibility.ps1
```

This only observes the system. A feature state of Unknown is not proof of absence. An already running hypervisor takes precedence over inconclusive CPU firmware flags.

Enable Hyper-V only after explicit consent using `scripts/Enable-HyperV.ps1` from an administrator PowerShell. It enables `Microsoft-Hyper-V-All` with `-NoRestart`; the result is in `artifacts/hyperv-setup.json`. Reboot manually when ready if required. Do not disable Windows protections.

After publishing, run `scripts/Install-DevOS.ps1` as administrator under the same Windows account that will run the launcher. It copies builds to `C:\Program Files\DevOS`, creates restricted `C:\ProgramData\DevOS`, and records the owner SID in HKLM. It refuses to overwrite an existing installation unless `-Update` is explicitly passed. Close DevOS before an update; VM data is preserved. This is a development installer for code you have reviewed, not a signed distribution installer.

Start `C:\Program Files\DevOS\launcher\DevOS.Launcher.exe` as the normal user. The launcher requests UAC only when it needs the broker. Over-the-shoulder elevation with a different administrator account is deliberately unsupported by the same-user IPC model. Installer outcomes are recorded in `artifacts/install-result.json`; do not infer success from the outer UAC process alone. `-Update -RepairEmptyRegistration` is limited to repairing an incomplete installation with matching protected owner ACLs and no VM data, and is not a general ownership-reset command.

## First Boot

1. Check Compatibility. Use the administrator check for complete feature state or Hyper-V permission errors.
2. Verify Debian Media. Requires the trusted GnuPG executable distributed with Git for Windows at `C:\Program Files\Git\usr\bin\gpg.exe`. See [media verification](guest/provisioning/README.md).
3. Create DevOS. This allocates 48 GiB; it requires at least 74 GiB free storage and 5 GiB free RAM. The VM has 2 vCPUs, 4 GiB static RAM and no attached network initially.
4. Explicitly select Installation Network / Ordinary NAT if needed. Only the existing Hyper-V Default Switch is used; no unrelated network settings change.
5. Start and Open Console. Follow [minimal Debian installation](guest/provisioning/README.md). Do not select a desktop environment or SSH server.
6. Shut down, Eject Installer while off, then start again to verify the installed guest boots from disk.
7. Shutdown, Disconnect Network, and Check Compatibility. The expected power state is OFF / UNVERIFIED.
8. Restart the launcher and confirm it observes the same VM ID and actual state. A permission error prompts an elevated read, never a guessed state.

## Failure And Recovery

There is no delete, forced power-off, suspend, checkpoint or automatic cleanup command. Failed creation preserves its registration stage and existing disk/VM for administrator diagnosis. A second Create is rejected. Do not manually delete resources merely to clear an error; first inspect `registration.json` and the matching Hyper-V ID/Notes. Configuration drift prevents start and other configuration changes; graceful shutdown remains available for a registered owned VM.

Broker requests contain one operation, never paths or VM IDs. A protected file lock serializes requests. Timeouts report an unknown state and require another query; cancellation does not imply rollback. The bounded audit file contains only timestamp, operation, success and error category. Boot failures inside Debian require console inspection; a running VM is not a successful boot test.

See [Phase 1 implementation and evidence](docs/phase1.md). The original Phase 0 documents remain unchanged. Phase 2 encryption is not started. No license has been chosen yet.
