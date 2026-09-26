# DevOS

DevOS is a disposable development environment project with a Windows launcher, constrained broker, Hyper-V lifecycle checks, Debian guidance, and an optional Jev diagnostic client.

## Status

Phase 1 is a Hyper-V prototype. It reports compatibility, validates an owned disposable VM, and handles broker IPC failures safely. Encryption is not implemented in the Hyper-V launcher. Windows Home reports `WINDOWS_EDITION_UNSUPPORTED` because Hyper-V is unavailable there.

Phase 2 is being explored with free VirtualBox. The Debian guest should use encrypted LVM/LUKS2 and synthetic test data only. VirtualBox is not controlled automatically by the repository yet.

## Build and test

```powershell
.\scripts\Build.ps1
dotnet run --project tests\DevOS.Tests\DevOS.Tests.csproj -c Release -- --inspect
```

The build runs C# and PowerShell tests and publishes self-contained output under `artifacts/`. Generated output is ignored and can be regenerated.

## Jev assistant

The optional client is in `jev/DevOS.Jev`. Set the key only in the current process environment:

```powershell
$env:JEV_API_KEY = "your-key"
```

Never commit the real key. `.env` files, credentials, VM disks, ISO media, logs, and build output are ignored; `.env.example` remains tracked. Jev failures fall back to normal investigation.

## VirtualBox Phase 2 setup

Create `DevOS-Phase2` with 2 CPUs, 4 GiB RAM, a 48 GiB disk, EFI, and NAT networking. Attach the Debian 13 amd64 netinst ISO and choose guided encrypted LVM during installation. Never use real private data in this VM.

## Transfer cleanup

Generated `bin`, `obj`, `artifacts`, `.tools`, VM images, installer media, logs, and local environment files are excluded from transfer. Run `scripts\Build.ps1` on the destination to regenerate output.

## Security boundary

This is not yet a secure personal-data environment. Phase 2 is complete only after encrypted cold unlock, recovery, wrong-passphrase, and shutdown-relock tests on a disposable guest.
