# DevOS Threat Model

Status: Phase 0 design, not a security certification or a verified implementation.

## Protected Assets And Boundary

Protect guest documents, source code, application state, credentials and encryption secrets. The primary confidentiality boundary is a powered-off VM whose private filesystem is inside LUKS2. Windows, Hyper-V, boot software, the launcher/broker and trusted installation sources form part of the trusted computing base.

An attacker may browse the Windows account or copy the VHDX while DevOS is off. They may know the format and source code. Security depends on established encryption and strong credentials, not a hidden path or proprietary disk format.

## Threats And Responses

| Threat | Proposed response | Residual limitation |
| --- | --- | --- |
| File Explorer, search, recent-files exposure | No guest sharing; encrypted root; no host indexing of internal files | Disk path, capacity and existence remain visible |
| Offline copy of virtual disk | LUKS2, strong passphrase, calibrated Argon2id | Offline guessing remains possible; UI throttling cannot prevent it |
| Accidental clipboard or drive sharing | No enhanced-session agents/redirection; sharing off | Deliberate paste/export, screenshots and manual copying can expose data |
| Guest plaintext in logs, swap or temporary files | All persistent guest data under encrypted root | Boot partitions and metadata remain visible |
| Saved VM memory revealing keys | No save/suspend lock, no checkpoints, shutdown lock | Host hibernation, crash dumps and forensic memory remnants are outside a LUKS-only guarantee |
| Untrusted guest or imported file | Hypervisor boundary, limited integration, bounded future transfer protocol | Hypervisor vulnerabilities and malicious guest software still matter |
| Broker abused for host privilege escalation | Narrow operations, caller authorization, owned resources, protected binaries | Broker defects remain security-critical |
| Guest network reaches host services | Offline/private-switch modes, tested NAT/firewall policies | NAT alone provides no host isolation; internet services can receive guest data |
| Disk deletion, corruption or ransomware | Independent offline encrypted backups, restore exercises | Encryption does not prevent destruction |
| Tampered boot or rolled-back ciphertext | Verified installation media, Secure Boot, updates, controlled storage ACLs | No complete evil-maid, authenticated-storage or rollback guarantee |

## Explicit Non-Goals

DevOS does not protect a running, unlocked VM from an administrator/kernel-level attacker controlling Windows. Such an attacker may capture keyboard input, screen output, guest memory and keys, or change virtualization behavior. A malicious process running as the same interactive Windows user can also capture or manipulate ordinary UI paths; guest-side passphrase entry is not a trusted input path.

An unlocked desktop is available to someone who can use its console. Protection against casual Windows account access therefore principally applies while DevOS is cryptographically locked. Desktop lock reduces casual access but leaves disk keys active. Theft while the host is asleep or hibernated is not equivalent to a clean VM shutdown.

No guarantee is made against physical RAM forensics, host paging/dump artifacts, malicious firmware, compromised supply chains, denial of service, file size/timing observation, or voluntary plaintext exports. Host disk encryption can complement LUKS but cannot make a compromised running Windows host trustworthy.

## Security Invariants

1. Guest private data is written only to encrypted guest storage once Phase 2 is verified.
2. The launcher never marks an unverified or saved VM as cryptographically Locked.
3. No secrets enter DevOS host configuration, command-line arguments, logs or source control.
4. No host directories, clipboard synchronization or transfer agents are enabled by default.
5. Broker operations cannot target arbitrary host paths, VMs or programs.
6. Failed isolation configuration leaves networking disconnected or reports Error without claiming success.
7. Application restart and crashes trigger observation of real state, not restoration of a cached Locked label.

## Review Triggers

Revisit this model before adding a guest agent, enhanced console, transfer/export channel, network service, checkpoints, unattended unlock, TPM integration, USB passthrough, multiple users or disposable clones. Each changes the trust boundary. Keep a record of actual verification results beside the tests; this document alone proves none of the invariants.
