# Backup Overview

This document describes the overall backup strategy that `rsync2backup` is a part of,
and gives an honest assessment of the design — what is solid, and where care is needed.

## The Vision: A Multi-Stage Backup Pipeline

The full backup strategy consists of four stages. `rsync2backup` implements **stage 1**;
the remaining stages are handled by additional tooling built on top of it.

1. **Live mirror (this project, `rsync2backup`)**
   Keep an up-to-date copy of the client's data on a remote backup server. Every time
   the client runs, changes are synchronized to the server via `rsync` over SSH, so the
   server always holds a current mirror of the source filesystem.

2. **Full and incremental backups on the server**
   On the backup server, scheduled jobs create full and incremental backups (snapshots)
   from the mirrored data at regular intervals. This gives point-in-time recovery
   capability in addition to the live mirror.

3. **Off-site storage on external disks and in the cloud**
   The generated backups are transferred to external disks (for local off-server copies)
   and to cloud storage. Cloud copies are stored **encrypted**, so that the cloud
   provider never sees plaintext data.

4. **Verification through restore tests**
   Backups are regularly verified by restoring them from both the external disks and
   from the cloud, ensuring that the stored backups are actually usable and not
   silently corrupted.

## Is the Idea Solid?

**Short answer: yes.** The overall idea follows well-established backup principles.
A few design details, however, will decide whether the result is robust or fragile
in practice.

### What is good about it

- **Follows the 3-2-1 rule (and then some).**
  You end up with: the original, a live mirror on the server, snapshots on the server,
  copies on external disks, and encrypted cloud copies. That is actually closer to
  *3-2-1-1-0* (the modern variant: at least one off-site copy, zero verification errors).
  Very sound.
- **Separation of concerns per stage.**
  Sync ≠ backup ≠ archival ≠ verification. Treating them as distinct stages is the right
  architectural instinct. Many home-grown backup solutions fail because they conflate them.
- **Docker for a cross-platform client.**
  Pragmatic. Avoids re-implementing rsync/ssh behavior on Windows and macOS.
- **Encryption before cloud upload.**
  Correct threat model — never trust the cloud provider with plaintext.
- **Explicit restore verification.**
  This is the single most-often-skipped step in real-world backup setups. Including it
  from the start is excellent.

### Where the design needs care

1. **A live mirror is *not* a backup.**
   `rsync --delete` propagates deletions and corruption (including ransomware) to the
   server within minutes. Stage 1 alone protects only against **hardware loss**, not
   against user error, malware, or bit-rot.
   → Stage 2 (snapshots) is therefore **not optional**; it is what turns this into an
   actual backup system. Make sure stage 2 exists *before* relying on the setup.

2. **Choice of snapshot tool matters.**
   Rather than rolling a custom "full + incremental" scheme, use a proven tool on the
   server side:
   - **restic**, **BorgBackup**, or **Kopia** — all provide deduplicated, encrypted,
     incremental-forever backups with built-in verification (`restic check`, `borg check`).
   - This also solves stage 3 cleanly: restic/Borg/Kopia can push directly to S3, B2,
     or any rclone-supported cloud with encryption already applied.
   - It would arguably allow **collapsing stages 2 and 3** into a single tool, which
     is simpler and less error-prone than a custom pipeline.

3. **Key management is the hidden hard problem.**
   Encryption keys for cloud backups must themselves be backed up — but *not* into the
   same backup. Losing the key = losing every cloud backup. Plan for:
   - Offline copies of encryption keys (paper, hardware token, sealed envelope).
   - A documented recovery procedure that a second person could execute.

4. **Immutability against ransomware.**
   - Snapshots on the server should be **append-only** from the client's perspective
     (the client's SSH key must not be able to delete snapshots).
   - The cloud target should support **object lock / versioning** (e.g. S3 Object Lock,
     B2 file locking) so that an attacker with server access still cannot destroy the
     cloud copy.

5. **Verification must be automated and alerted.**
   "Regularly verify" only works if:
   - It runs on a schedule (cron / systemd timer).
   - Failures produce a loud notification (email, Pushover, etc.).
   - A silent verification that nobody looks at is worse than none, because it creates
     false confidence.

6. **Rsync-over-SSH scaling caveats.**
   For large or many-small-file datasets, rsync's file-list scan becomes slow. If the
   source grows to millions of files, consider `rsync --files-from`, or switch the sync
   stage itself to restic/Borg/Kopia (they scale better because they track state).

7. **Windows-specific gotchas via Docker.**
   - File permissions and ownership from Windows bind-mounts do not round-trip cleanly;
     symlinks, ACLs, alternate data streams, and reparse points can be lost.
   - Line endings and locale on paths are already a concern (see the `dos2unix` calls
     in the Dockerfile).
   - For a Windows *system* backup (not just user data), rsync-in-Docker cannot see VSS
     snapshots, so files that were open during sync may be captured inconsistently.
     For pure "documents & projects" this is fine.

## Verdict

The **strategy** is solid — arguably better than what most people run at home. The main
risk is not the concept but the **implementation choices for stages 2–4**.

Concrete recommendation:

> Keep stage 1 (this repository) as the cross-platform rsync mirror, but implement
> stages 2 and 3 with an existing deduplicating, encrypted backup tool
> (restic / BorgBackup / Kopia) rather than a custom full+incremental scheme.
> Stage 4 then becomes `restic check --read-data` (or the equivalent) on a schedule,
> plus a periodic scripted test-restore into a scratch Docker container — which closes
> the loop nicely with the Docker-based approach already in use.

With that in place, the plan is not just solid — it is genuinely production-grade for
personal and small-office use.

