# Phase 1 Implementation And Evidence

Date: 2026-09-25. Status: INCOMPLETE, awaiting Windows reboot and successful media retrieval before VM integration testing. Phase 2 has not started.

## Implemented Architecture

WPF/.NET 10 normal-user launcher, a short-lived UAC broker, and a shared Hyper-V library with an embedded fixed PowerShell backend. The broker accepts one bounded, typed operation over a local named pipe, with an explicit same-user ACL, network-client denial, session checks and reciprocal process-ID verification. It accepts no VM identifiers, filesystem paths, programs or shell commands from the UI. A protected file lock serializes operations across processes. No permanently elevated UI or broad Hyper-V Administrators membership is used.

The owner registration and VM files live under protected ProgramData. VM identity consists of a persisted GUID plus an unpredictable Notes marker; both are checked before operations. A failed create preserves its stage, disk and any VM ID for diagnosis. Start and configuration changes require a compliant configuration. Shutdown is still available for an owned VM with drift. Actual observed power is mapped separately from provisioning/configuration status; no cryptographic Locked state exists in the Phase 1 model.

Media preparation pins Debian 13.7.0 amd64, verifies a signed SHA-256 manifest against Debian's published CD signing fingerprint, hashes the ISO and records provenance. The implementation has not yet completed that real download/verification flow. No ISO was attached or booted. The application cannot proceed through Create without the verified record and matching hash.

## Build And Unit Tests

PASS: local Microsoft .NET SDK 10.0.401 download verified against SHA-512 release metadata. SDK stored in ignored `.tools/dotnet`.

PASS: Release solution build, zero warnings and zero errors. Self-contained win-x64 launcher and broker published into `artifacts/launcher` and `artifacts/broker`.

PASS: eight C# test groups covering fixed configuration, ownership helper, power-state mapping, failed observations, restart reconciliation, managed paths and strict broker request parsing. Oversized requests, unknown properties, duplicate operations and numeric enum values are rejected.

PASS: twelve tests against the actual production PowerShell functions: valid ownership; foreign/malformed IDs; altered marker; partial creation; missing media; qualified integration-service identifiers; valid configuration; dynamic RAM; foreign disk; disabled Secure Boot; and missing shutdown integration. These use controlled fixtures, not a real VM.

Commands:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File scripts\Build.ps1
.\.tools\dotnet\dotnet.exe run --project tests\DevOS.Tests -c Release --no-build -- --inspect
.\.tools\dotnet\dotnet.exe run --project tests\DevOS.Tests -c Release --no-build -- --broker-inspect
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests\Launcher.Smoke.ps1
```

## Integration Results

| Check | Result | Evidence / limitation |
| --- | --- | --- |
| Read-only compatibility backend | PASS | Real JSON observation identifies Windows 11 Pro, active hypervisor, missing management components and pending reboot |
| Enable approved Hyper-V feature | PASS | `artifacts/hyperv-setup.json`: Success=true, RestartNeeded=true, Microsoft-Hyper-V-All, 2026-09-25T08:38:07Z |
| Hyper-V operational after reboot | NOT RUN | Laptop was not rebooted; VMMS and module are not available yet |
| Install restricted app/data directories | PASS | Files exist under Program Files; ACLs show SYSTEM/Administrators FullControl and owning user ReadAndExecute |
| Installed elevated broker IPC | PASS | Test returned real observation at 2026-09-25T08:50:31Z through the installed broker |
| Launch installed WPF application | PASS | UI Automation found rendered compatibility results and the exact Phase 1 warning; process PID 20628 at test time |
| Debian media retrieval | FAIL / blocked | Official checksum endpoint closed one request; bounded curl retry timed out after 40 seconds with zero bytes |
| Signed manifest and ISO digest verification | NOT RUN | No media retrieved; no verified.json or trusted ISO exists |
| Fixed VHDX and VM creation | NOT RUN | Reboot/media prerequisites unmet; no DevOS VM or disk created |
| Actual VM configuration readback | NOT RUN | No VM exists |
| VMConnect / Debian boot | NOT RUN | No VM exists; opening the Windows launcher is not VM boot evidence |
| Guest graceful shutdown | NOT RUN | No guest exists |
| Launcher restart with an existing running/off VM | NOT RUN | Unit reconciliation passes, but real VM restart recovery is not demonstrated |

The latest broker observation reported approximately 2,964 MiB available RAM and 98 GiB free storage. Available memory is below the prototype's 5 GiB preflight threshold for starting its 4 GiB guest. Close unnecessary applications before the VM test. Total host RAM is approximately 16 GiB.

## Intended Versus Actual VM Configuration

Actual: no VM, no VHDX, no attached ISO, no guest state. The values below are implemented creation policy, not observed VM properties:

| Setting | Creation policy |
| --- | --- |
| Name | DevOS-Phase1 |
| Generation | 2 |
| CPU | 2 vCPUs |
| RAM | 4 GiB static; dynamic memory disabled |
| Disk | 48 GiB fixed VHDX |
| Firmware | Secure Boot On, MicrosoftUEFICertificateAuthority |
| Automatic start / stop | Nothing / ShutDown |
| Checkpoints | Disabled; automatic checkpoints disabled |
| Integrations | Shutdown, heartbeat, time synchronization only |
| Network | Disconnected initially; explicit Default Switch connection labeled Installation Network / Ordinary NAT |
| Desktop / encryption | Neither configured |

## Issues Found And Fixed During Testing

The real backend initially exceeded Windows' command-line length limit. It now sends the embedded script through redirected stdin with a short constant bootstrap. An early exit in the embedded script suppressed buffered output; it was changed to return normally, and the actual read-only observation then passed.

The first IPC attempt used CurrentUserOnly and failed across UAC tokens. Explicit owner-SID pipe permissions replaced that default. The installed binary was initially stale because installation owner registration was incomplete; a constrained empty-installation repair and update receipt were added. After repair, the real broker IPC check passed. These failed attempts were not counted as successful integration tests.

## Files Created

- `DevOS.sln`, `global.json`, `Directory.Build.props`, `.gitignore`, `README.md`.
- `launcher/DevOS.Launcher/`: project, manifest, App.xaml/code, MainWindow.xaml/code.
- `launcher/DevOS.Broker/`: project and Program.cs.
- `virtualization/DevOS.HyperV/`: project, Models.cs, BrokerClient.cs, PipeProtocol.cs, PowerShellBackend.cs, Scripts/HyperV.ps1.
- `scripts/`: Install-LocalSdk.ps1, Build.ps1, Check-Compatibility.ps1, Enable-HyperV.ps1, Install-DevOS.ps1.
- `tests/DevOS.Tests/`: project and executable test harness; `tests/PowerShellPolicy.Tests.ps1`; `tests/Launcher.Smoke.ps1`.
- `guest/provisioning/README.md` and this report.

The three Phase 0 documents were not edited. Git was not reinitialized; no commit or remote change was made. No empty guest desktop/security directories or placeholder projects were created.

## Limitations And Remaining Acceptance

This is an unencrypted disposable prototype. It cannot protect private data at rest and makes no claim against a compromised Windows host. The basic console has no guest enhanced-session/RDP service installed by this project, but clipboard, drive sharing and console behavior still require real guest tests. NAT is not host/LAN isolation. Guest boot readiness is unknown unless verified in the console. No forced shutdown, snapshot, recovery secret or LUKS implementation exists.

Same-account UAC elevation is supported; another administrator's credentials are not. The development installer and binaries are unsigned. GnuPG from the protected Git for Windows installation is a current media-verification prerequisite. Network downloads, shutdown timeout behavior, cross-user IPC rejection, real filesystem access denial and adversarial reparse-point scenarios need additional live coverage before stronger assurance claims.

The fixed constants follow Phase 0. The concrete Debian point release is pinned at 13.7.0; actual signed media validation is still required. Automated installation is deferred to a manual Debian text-console install for this smallest prototype. Framework-free executable tests avoid adding test-runner dependencies. No final network security modes or desktop placeholders were added.

Next: reboot Windows with the user's approval; query Hyper-V again; resolve Debian endpoint reachability and complete signature/digest verification; free sufficient RAM; create and inspect the VM; install and boot minimal Debian; gracefully shut it down; verify OFF / UNVERIFIED; restart the launcher against both real power states. Record every result. Phase 1 is complete only after that sequence succeeds, and Phase 2 still requires separate approval.
