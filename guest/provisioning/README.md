# Phase 1 Debian Installation

Use only synthetic test data. The installed filesystem is intentionally unencrypted in this phase.

## Pinned Media

The prototype pins `debian-13.7.0-amd64-netinst.iso` from `https://cdimage.debian.org/debian-cd/13.7.0/amd64/iso-cd/`. Availability and successful download must still be verified on the target host. Never silently fall back to another version, an unsigned mirror manifest or a locally supplied ISO.

The broker downloads SHA256SUMS and SHA256SUMS.sign, obtains the Debian CD public key from keyring.debian.org, and checks the detached signature using GnuPG. The accepted signing fingerprint is `DF9B9C49EAA9298432589D76DA87E80D6294BE9B`, published on [Debian's authenticity verification page](https://www.debian.org/CD/verify). A different key requires an explicit reviewed pin update. A successful import alone is insufficient: verification must exit successfully and report that exact fingerprint in VALIDSIG.

It then finds the exact filename in the signed manifest, downloads the ISO, computes SHA-256 and compares it. Only success writes `C:\ProgramData\DevOS\media\verified.json` with filename, version, digest, source, signing fingerprint and UTC verification timestamp. Creation and subsequent starts with media attached rehash the ISO against that protected record. No verified record means no attachment. Interrupted downloads are preserved and fail verification; an administrator must investigate the partial ISO before removing/retrying it.

The GnuPG home contains public verification material only and is under the protected media directory. Standard users cannot substitute media, verification records, the signing key or broker code. GnuPG is a local installation prerequisite, not an arbitrary executable path accepted from the UI.

## Manual Guest Setup

After verified media is attached, use Basic VMConnect to run the Debian text installer. Choose a local disposable account, enter its password directly in the guest, and do not record it in host logs. Use guided whole-disk partitioning on the single 48 GiB virtual disk without encryption for Phase 1. Confirm the disk capacity inside the guest before partitioning.

In software selection, deselect Debian desktop environment and SSH server. Keep standard system utilities. Internet package installation requires the explicitly chosen ordinary NAT network. Do not install xrdp, host drive mounting tools or clipboard integration. Use Debian's standard kernel and Hyper-V shutdown integration.

After installation, shut down through the guest or launcher, eject the ISO, and boot from the VHDX. Verify `/etc/os-release` identifies Debian 13 and `uname -m` reports x86_64. Record these non-secret outputs manually as boot evidence. Request shutdown from the launcher and confirm Hyper-V transitions to Off. Repeat launcher restart while off and while running. VM heartbeat alone does not satisfy this acceptance test.

XFCE and LUKS2 are outside this phase. Never reuse this unencrypted guest as a secure environment merely by changing its UI label.
