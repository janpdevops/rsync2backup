# Integration test — rsync2backup

A self-contained end-to-end test that exercises the full client/server sync
loop with real Docker containers and real rsync/SSH traffic.

## What it does

1. **Builds** both images (`janpdev/rsyncbackup-common:v0.1` and
   `rsync2backup-client:test`) from the repository.
2. **Creates** an isolated scratch working directory under `%TEMP%` with:
   * empty `server-data/` (the backup destination)
   * `client-source/` populated from `fixtures/`:
     * `hello.txt`
     * `subdir/nested.txt`
     * `todelete.me`
3. **Runs the client once** — this is the first-run key-generation pass; it
   writes `ssh_key` / `ssh_key.pub` into the client key mount and does **not**
   sync anything (that is the current script's designed behaviour).
4. **Places the generated public key** into the server's `keys/` mount so the
   `linuxserver/openssh-server` image installs it into `authorized_keys` on
   startup.
5. **Starts the server** on an isolated docker network, waits for SSH to
   answer on port 2222.
6. **Runs the client again (initial push)**. Verifies that the server side now
   contains:
   * `upload/hello.txt`
   * `upload/subdir/nested.txt`
   * `upload/todelete.me`
7. **Mutates the client source**:
   * deletes `todelete.me`
   * adds a new file `add`
8. **Runs the client a third time (mutation push)**. Verifies that the server
   side now:
   * **has** `upload/add`
   * **no longer has** `upload/todelete.me`
   * still has `upload/hello.txt` and `upload/subdir/nested.txt`
9. **Cleans up**: stops the server container, removes the docker network and
   the scratch directory.

If any assertion fails, the script throws and the `finally` block still runs
the cleanup (unless `-KeepScratch` is used).

## Requirements

* Windows PowerShell 5.1 or PowerShell 7+
* Docker Desktop (or any local Docker engine)
* Network access on first run so Docker can pull
  `linuxserver/openssh-server` and `alpine:3.20`

## Usage

From this directory:

```powershell
./run-test.ps1                 # build images + run full test
./run-test.ps1 -SkipBuild      # reuse existing local images
./run-test.ps1 -KeepScratch    # keep the temp working dir for inspection
```

Expected runtime: ~30-60 seconds on a warm cache.

## Layout

```
tests/integration/
├── README.md            (this file)
├── run-test.ps1         (test orchestrator)
└── fixtures/            (initial client contents)
    ├── hello.txt
    ├── subdir/
    │   └── nested.txt
    └── todelete.me
```

## Notes / known quirks exercised by the test

* The test intentionally does **not** use the auto-generated server
  `docker-compose.yml` produced by the first client run — that file bakes in
  Windows-only paths and does not describe an isolated test topology.
  Instead the server is started directly with `docker run` and its own
  mounts, but with the same image and the same env variables the compose
  file would set (`PUBLIC_KEY_DIR`, `USER_NAME`, `PUID`, `PGID`).
* The rsync source path `/upload` is used **without** a trailing slash, which
  matches the current client script (`rsync2backup.sh`) and means all files
  end up under `/data/upload/...` on the server rather than directly under
  `/data/`. When the script is fixed to use a trailing slash, the `syncedRoot`
  path in `run-test.ps1` will need to change accordingly.
* On Windows bind mounts POSIX ownership is not enforced, so the
  `chown -R transfer:transfer /data` step inside the server container is a
  no-op on Windows but keeps the test portable to Linux hosts.

## Troubleshooting

* **Test fails at "SSH did not come up"** — the server container probably
  crashed during startup. Rerun with `-KeepScratch` and inspect its logs:
  ```powershell
  docker logs <server-container-name>
  ```
  The container name is printed by the script as
  `rsync2backup-test-server-<timestamp>`.
* **Test fails at "todelete.me on server"** — the initial rsync push did not
  succeed. Look for rsync errors in the "Client run #2" output; the most
  common cause is a missing public key on the server, i.e. the pubkey was
  copied *after* server startup instead of before.
* **Docker build errors** — make sure Docker Desktop is running and that the
  repo path does not contain any parent directory named the same as a
  reserved Docker Hub namespace.

