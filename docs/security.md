# DevOS Security Design And Verification

Status: Proposed controls and acceptance tests. All runtime tests below are NOT RUN. There is no secure usable environment yet.

## Required Defaults

- Encrypt root, home, application state, logs and swap with LUKS2. Only boot software and structural metadata are outside it.
- Keep clipboard synchronization, shared folders, drive redirection, drag/drop, file-copy integration and passthrough off.
- Start in Offline mode after provisioning; require an explicit network choice for installation and updates.
- Disable automatic and manual checkpoints in the supported policy. Never Save/Pause as a cryptographic lock.
- Keep host and guest Secure Boot enabled where supported; troubleshoot failed signed boot rather than silently weakening it.
- Use a standard-user UI and a narrowly scoped elevated broker. Do not disable Defender, VBS or other host protections.
- Store no unlock secret in host configuration, logs, command lines or unattended installation media.

## Authentication And Secrets

Use the guest's established cryptsetup prompt for disk authentication. Calibrate Argon2id using guest resources, and test recovery from incorrect entry. Add bounded interactive retry delays using established boot tooling if supported; do not claim this limits attacks on a copied disk. Login throttling and disk-unlock throttling are separate mechanisms.

Generate the recovery secret with the guest OS cryptographic random source and enroll it in a separate keyslot. Test both unlock paths before relying on the installation. No developer key, universal password or plaintext keyfile in /boot. Minimize secret lifetime in memory; never promise forensic zeroization across Windows, Hyper-V and physical RAM.

Logs should use allowlisted event fields: event ID, VM ID, operation, duration and sanitized error category. Avoid dumping process output, guest messages, environment variables, file contents or exception objects indiscriminately. Redact sensitive paths where practical. Apply bounded retention and restrictive ACLs. Debug verbosity never enables secret logging.

## Implementation Requirements

Validate all configuration and IPC data at the privileged boundary. Use typed operations, trusted executable paths, parameter binding, resource ownership checks, path canonicalization and reparse-point defenses. Bound resource sizes and message lengths. Serialize conflicting operations per VM and make interrupted setup recoverable without deleting unrelated resources.

Pin build and guest inputs when implementation starts. Verify authenticated installer checksums, record provenance and keep security updates enabled through an explicit network-enabled maintenance flow. Review dependencies and privileged code changes. Backups and LUKS headers must follow the recovery constraints in architecture.md.

## Acceptance Tests

Use disposable VMs and synthetic unique markers. Never expose real credentials during test logging. Record host build, guest image digest, cryptsetup version, policy settings, commands used and observed results.

| ID | Procedure | Required evidence |
| --- | --- | --- |
| S01 | Create a unique marker in /home/dev/Documents/private.txt; shut down; inspect via ordinary Windows Explorer/search/recent files | Internal path and contents not exposed; container itself may be visible |
| S02 | Inspect a read-only copy of the off-state VHDX with trusted Linux tooling | Boot partitions contain only expected software; private root is LUKS2 and cannot mount without a credential |
| S03 | Check guest mounts, block devices, cryptsetup metadata and swap configuration | Root/home/logs/persistent temporary data/swap all map through the encrypted device; version/cipher/KDF recorded |
| S04 | Scan the virtual disk copy for multiple marker variants after forcing writes to persistent files | No marker found outside expected encrypted storage; absence alone is not proof of encryption |
| S05 | Reboot and enter wrong disk credentials, then correct credentials | Wrong entry never mounts root; correct entry recovers persisted marker; retry behavior recorded |
| S06 | Cold boot with the recovery secret; rehearse passphrase rotation on a disposable disk | Both recovery and rotation behave as documented; old backup/header revocation limitations demonstrated |
| S07 | Copy distinctive text and files in both directions with clipboard Off | No automatic synchronization; inspect installed agents and VMConnect explicit paste behavior separately |
| S08 | Inspect guest mounts and try known host-drive/share paths | No automatic C: mount, shared folder, drive redirection or file-copy integration |
| S09 | Offline mode: test DNS, IPv4, IPv6, TCP and UDP to host, LAN and internet | All network adapters disconnected; no working network path |
| S10 | Isolated mode: probe host/LAN/internet and inspect private-switch membership | No host adapter or uplink; no unapproved VM shares the switch |
| S11 | NAT mode: exercise permitted outbound traffic and probe host services/inbound paths | Effective policy matches documented reachability; DNS/IPv6 do not bypass restrictions |
| S12 | Lock with writes active, and repeat with a stalled guest | Normal path reaches Off and retains data; stalled path stays Locking/Error until resolved, never false Locked |
| S13 | Crash/restart launcher during running VM and setup | Running VM is detected; incomplete setup remains Unverified; no secret host temporary files |
| S14 | Test host shutdown, reboot, sleep and hibernate in a disposable environment | No saved-memory operation presented as cryptographic lock; unsupported/interrupted transitions reported |
| S15 | Attempt checkpoint/save via supported app paths; inspect externally created saved state | Operations unavailable; unexpected saved state/checkpoints invalidate secure status |
| S16 | Send malformed, oversized and unauthorized broker requests, arbitrary paths and foreign VM IDs | Requests rejected without effects on other host resources; standard user cannot replace broker code |
| S17 | Back up while Off; corrupt a copy; restore intact copy into a fresh offline VM | Corruption detected, recovery unlock works, original VM remains untouched; no memory snapshot included |
| S18 | Inspect logs, config, repository and setup artifacts using known synthetic secrets | No passwords, recovery secrets, keyfiles or guest file contents persisted on host by DevOS |
| S19 | Boot verified installation media and installed guest with Secure Boot enabled | Both boot on this machine; failures block readiness instead of disabling Secure Boot |

## Release Gates

Phase 1 may use an unencrypted disposable guest and must not display a secure/Locked badge. Its checks are build, compatibility detection, owned VM creation, console connection, boot, graceful shutdown and error handling. No private user data belongs there.

Phase 2 requires S01-S06, S12-S15, S18-S19 and inspection of the complete encryption layout. Basic sharing-off policy must already be checked. Phase 3 completes S07-S11 and S16 as the broker and network controls mature. Backup/transfer/auto-lock functionality needs additional feature-specific tests before Phase 5 release. A failed critical test blocks the corresponding security claim; skipped tests remain explicitly unverified.

Cryptographic Lock means the guest encrypted volume is no longer live-mounted and there is no known saved VM memory under supported DevOS policy. It does not certify that no recoverable key material exists anywhere in host memory, pagefiles, hibernation files or dumps. See threat-model.md for the boundary.
