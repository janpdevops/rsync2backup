# rsync2backup

A Docker-based, cross-platform backup sync solution. Synchronize local filesystem contents with a remote backup server over SSH, as the first step toward a complete, multi-stage backup strategy.

## Quick start

1. **Copy `.env.example` to `.env`** in the `client/` directory and edit to match your environment.
2. **Run the client for the first time** (generates SSH keys):
   ```bash
   cd client
   docker compose up
   ```
3. **Copy the generated public key** from `client/sshkeys/public/ssh_key.pub` to your backup server's authorized_keys for the transfer user.
4. **Start the backup server** (on your server machine):
   ```bash
   cd server
   docker compose up -d
   ```
5. **Run the client again** to sync your data:
   ```bash
   cd client
   docker compose up
   ```

For detailed information, see:
- **[Rsync-Backup.md](Rsync-Backup.md)** — Project overview and intent
- **[Backup-overview.md](Backup-overview.md)** — The full multi-stage backup strategy this is part of
- **[Code-review.md](Code-review.md)** — Known issues and future improvements
- **[tests/integration/README.md](tests/integration/README.md)** — How to run the integration test suite

## Features

- **Cross-platform**: Works on Windows, Linux, macOS via Docker
- **SSH-based**: Secure key-based authentication (no passwords)
- **Automatic key generation**: First run generates SSH keypair and server template
- **Push/pull modes**: Upload to server (push) or download from server (pull)
- **Deletion sync**: `rsync --delete` propagates removals to the backup destination
- **Persistent host keys**: Known hosts are saved between runs to detect MITM attacks

## How it works

```
┌─────────────────────────────┐
│ Client (Windows/Linux/macOS) │
│  ┌─────────────────────┐    │
│  │  /upload directory  │    │
│  │  (files to backup)  │    │
│  └──────────┬──────────┘    │
│             │               │
│        docker container     │
│        (rsync + ssh)        │
│             │               │
└─────────────┼───────────────┘
              │ SSH key-based auth
              │ rsync over SSH
              ▼
┌─────────────────────────────┐
│  Server (Backup destination) │
│  ┌─────────────────────┐    │
│  │  /data directory    │    │
│  │  (live mirror)      │    │
│  └─────────────────────┘    │
│                             │
│  docker container           │
│  (openssh-server + rsync)   │
└─────────────────────────────┘
```

This is **stage 1** of the backup pipeline. Stages 2–4 (snapshots, archival, verification) are handled by separate tools.

## License

Licensed under the [MIT License](LICENSE).

## Contributing

Bug reports and pull requests are welcome. Please see [Code-review.md](Code-review.md) for known issues and planned improvements.

