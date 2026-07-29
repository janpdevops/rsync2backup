ers# Code Review — `rsync2backup`

_Date: 2026-07-29_

## Summary

The project is at an early prototype stage. The **concept works** (client generates
keys, server accepts them, rsync transfers happen), but the code has substantial
issues in **security, correctness, portability, and maintainability** that must be
addressed before it can be recommended for real use — which the README itself
acknowledges ("don't use it yet!").

This document goes file by file, then lists cross-cutting concerns, then gives a
prioritized action list.

---

## 1. `client/scripts/rsync2backup.sh`

This is the heart of the client. Several bugs and design smells.

### Bugs

1. **`if ! [ -f ssh_key ]` uses a relative path**, but the working directory depends
   on how the container is invoked. `WORKDIR /data/sshkeys` in the Dockerfile fixes
   this in practice, but the script is fragile — one `cd` elsewhere breaks it.
   → Use an absolute path (`/data/sshkeys/ssh_key`) or a variable.

2. **`mv *.pub public`** — after `ssh-keygen -f ssh_key`, only `ssh_key.pub` exists.
   The glob works, but if a leftover `.pub` from a previous run is around, it moves
   everything. Prefer explicit: `mv ssh_key.pub public/`.

3. **Reading `$PUSH` when unset crashes under `set -u`.**
   `if (( $PUSH > 0 ))` fails hard if `PUSH` isn't exported. Also, if `PUSH` is a
   non-numeric string the arithmetic errors.
   → Default it: `PUSH="${PUSH:-0}"` and use `[ "$PUSH" -gt 0 ]`.

4. **Race condition / logic hole:** on the first run, the script generates keys and
   writes `docker-compose.yml` **but never actually runs rsync**. The user has to run
   `docker compose up` a second time. That's OK if documented, but the script
   silently exits with success — no message like "rerun after starting the server."
   Add a clear "next steps" print.

5. **`sed -i "s/#USER_NAME#/$USER_NAME/g"` etc. are unquoted.** If any variable
   contains `/`, `&`, or a newline, `sed` will corrupt the file or fail.
   → Use a delimiter unlikely to occur (`sed -i "s|#USER_NAME#|${USER_NAME}|g"`)
   *and* validate inputs.

6. **`docker-compose.yml` is written into the current directory (`/data/sshkeys`).**
   That means it lands in the user's key mount — which is confusing (compose file
   for the *server* stored next to the client's private key). It should be written
   to a separate output dir the user mounts, e.g. `/data/server-compose/docker-compose.yml`.

7. **`cp -r .ssh ~` on every subsequent run** unconditionally copies persisted `.ssh`
   over the container's home. If it doesn't exist, `cp` errors and (without `set -e`)
   execution continues.
   → Guard with `[ -d .ssh ]` (which you already have for the outer `if`, but the
   inner `cp` is inside that guard already; still worth using `-T` or an explicit
   target: `cp -rT .ssh "$HOME/.ssh"`).

8. **After push, `cp -r ~/.ssh .` writes the host-key-augmented `.ssh` back into
   `/data/sshkeys`.** Fine in principle — but it will happily overwrite anything in
   there and it isn't done in the pull branch. Both branches should update
   `known_hosts`.

9. **Shell quoting inside the `-e` string is broken-looking:**
   ```
   -e "ssh -i /data/sshkeys/ssh_key  -o \"StrictHostKeyChecking ${STRICT_HOST_CHECKING}\"  -p ${RSYNC_PORT} "
   ```
   The `-o` value doesn't need to be quoted inside the outer double-quotes — rsync
   passes the string to a shell, and the escaped quotes actually reach that shell as
   literal `"` characters. It works by accident. Cleaner:
   ```bash
   rsync -av --delete \
     -e "ssh -i /data/sshkeys/ssh_key -o StrictHostKeyChecking=${STRICT_HOST_CHECKING} -p ${RSYNC_PORT}" \
     /upload/ "${USER_NAME}@${RSYNC_SERVER}:/data/"
   ```

10. **Trailing-slash asymmetry between push and pull.** `rsync -av /upload user@host:/data`
    copies `/upload` **as a subdirectory** into `/data`, giving `/data/upload/...`.
    The pull path does the same reversed. Was that intended? For a mirror, you almost
    always want `/upload/` (with trailing slash) → `/data/`.

11. **`--delete` is only in the push path.** On pull, deletions from the server are
    not reflected locally. Fine for restore semantics, but worth being explicit
    about in a comment.

12. **No `set -euo pipefail`.** Any command can fail silently. Add:
    ```bash
    set -euo pipefail
    ```
    at the top and remove reliance on non-strict mode.

13. **Missing required-variable validation.** The script assumes `RSYNC_SERVER`,
    `RSYNC_PORT`, `USER_NAME`, `RSYNC_UID`, `RSYNC_GID` are all set. If any is
    missing, either the rsync command silently misbehaves or the sed templating
    leaves `#PLACEHOLDER#` strings in the output. Add explicit checks.

14. **The comment on line 26–27 ("create add-user-skript, pass it to rsync-server")
    is a TODO in a code path that reaches production.** Either implement it or
    remove the ambiguity.

15. **`echo Rsync in push mode`** — unquoted, which works, but inconsistent with the
    rest. Nit.

### Missing features

- No logging with timestamps.
- No exit-code propagation from rsync (fine because there's no `set -e`, but that's
  itself the problem).
- No dry-run switch (`RSYNC_DRY_RUN=1` → `-n`).
- No bandwidth limit switch (`--bwlimit`).
- No `--partial --partial-dir` for interrupted transfers over slow links.

---

## 2. `client/Dockerfile`

```dockerfile
FROM  janpdev/rsyncbackup-common:v0.1
```

- **Base image is versioned to `:v0.1`.** OK for reproducibility, but the client
  compose file references `janpdev/rsyncbackup-client:v0.11` while the README says
  build `v0.1`. → Version drift. Standardize on a single scheme and document it.
  Consider `ARG BASE_VERSION` so both stay in sync.
- **`LABEL MAINTAINER`** is deprecated. Use
  `LABEL org.opencontainers.image.authors=...` (which the server Dockerfile already
  does correctly).
- **`RUN chmod u+x /usr/bin/rsync2backup.sh` is redundant** — the `COPY --chmod=u+x`
  already did it.
- **`RUN dos2unix ...` in three separate layers** bloats the image. Combine:
  ```dockerfile
  RUN dos2unix /usr/bin/rsync2backup.sh /tmp/template1.yml /tmp/template2.yml \
      && chmod +x /usr/bin/rsync2backup.sh
  ```
- **No `.dockerignore`** in the repo. `.git`, `.idea`, `.obsidian` will be shipped
  into the build context. Add a `.dockerignore`.
- **No `HEALTHCHECK`**, no non-root user. The container runs as root; it doesn't
  need to for rsync client work.
- **`ENTRYPOINT ["rsync2backup.sh"]` with no `CMD`** — fine, but arguments passed
  via `docker run` will be positional args to the script, which the script ignores.
  Consider parsing them.

---

## 3. `server/Dockerfile`

```dockerfile
FROM linuxserver/openssh-server:latest
```

- **`:latest` is a reproducibility hazard** — image rebuilds pick up unrelated
  upstream changes. Pin to a specific digest or tag
  (e.g. `linuxserver/openssh-server:9.6_p1-r0-ls148`).
- **Trailing whitespace / empty `\` on lines 7–8** — the `RUN` command effectively
  ends with `rsync` and nothing follows. Works, but noisy.
- **No hardening** on top of the upstream:
  - `AllowUsers` / `Match User` restricted to only the backup user.
  - Force `ForceCommand internal-sftp` or restrict to rsync via `authorized_keys`
    `command="..."` (see cross-cutting note below).
  - Disable password auth explicitly (upstream already does, but making it explicit
    here is good defense-in-depth).
- **`LABEL version=0.1`** should be `org.opencontainers.image.version`.

---

## 4. `client/docker-compose.yml`

```yaml
image:  janpdev/rsyncbackup-client:v0.11
...
- RSYNC_SERVER=172.26.192.1
- RSYNC_UID=2001
volumes:
- source: C:\nobackup\clienttest\keystuff
- source: C:\Users\jan\Documents\projects\rsync2backup\
```

- **Version mismatch** with README (`v0.1` vs `v0.11`).
- **Hard-coded hostnames and Windows paths** commit personal setup details to a
  public repo. This is the number-one issue for a GitHub release. Convert to a
  **`.env` file**:
  ```yaml
  environment:
    - RSYNC_SERVER=${RSYNC_SERVER}
    - RSYNC_PORT=${RSYNC_PORT}
    - USER_NAME=${USER_NAME}
    - RSYNC_UID=${RSYNC_UID}
    - RSYNC_GID=${RSYNC_GID}
    - PUSH=${PUSH:-1}
  volumes:
    - ${KEY_DIR}:/data/sshkeys
    - ${SOURCE_DIR}:/upload
  ```
  and ship a `.env.example`.
- **`RSYNC_GID` is not set** in the compose file although the script references it
  — it will be empty, and the generated server compose will have `PGID=`.
- **`version: "3.8"`** is obsolete — modern Compose ignores it. Remove.
- **`/upload` is bind-mounted read-write** for push. In push mode it can be
  read-only:
  ```yaml
  - type: bind
    source: ${SOURCE_DIR}
    target: /upload
    read_only: true
  ```
  This is a small but real safety win (defends against a script bug that could
  delete source data).

---

## 5. `server/docker-compose.yml`

```yaml
version: "2.1"
- C:\nobackup\server\config:/config
- C:\nobackup\server\transfer_target:/data
- C:\nobackup\server\keystuff\public:/keys
ports:
- 2001:2222
```

- Same **hard-coded Windows paths and version pinning** issues as the client.
- **Server is exposed on `2001:2222` bound to all interfaces.** For a server that
  only serves LAN or VPN traffic, bind to a specific interface:
  `127.0.0.1:2001:2222` or the LAN IP. If it truly is internet-exposed, add
  fail2ban / rate limiting outside the container.
- **`PUID=1000/PGID=1000`** hard-coded here, but the client sends `RSYNC_UID=2001`.
  Ownership on `/data` will mismatch what the client believes. Push works because
  rsync-over-ssh runs as the login user, but any script logic assuming `PUID` and
  `RSYNC_UID` match will silently break.
- The `USER_NAME=transfer` is set on the server side but there is no mechanism to
  ensure it matches the value the client used to *generate the key*. Document this
  coupling or auto-derive.

---

## 6. `client/scripts/template1.yml` + `template2.yml`

The `cat template1.yml public/ssh_key.pub template2.yml > docker-compose.yml` trick
is clever but fragile:

- **The public key is a single long line.** Injecting it between two YAML fragments
  works only because it lands on the same physical line as `- PUBLIC_KEY=` in
  `template1.yml` (which ends with `PUBLIC_KEY=` and *no newline*). But
  `template1.yml` as shown in your workspace does end with a normal newline
  (12 lines). If Git or an editor normalizes EOL, this **will produce broken YAML**
  like:
  ```yaml
  - PUBLIC_KEY=
  ssh-ed25519 AAAA...
  ```
  which is not valid.
  → Either strip trailing newline explicitly in the script:
  ```bash
  printf '%s' "$(cat /tmp/template1.yml)" > docker-compose.yml
  cat public/ssh_key.pub >> docker-compose.yml
  cat /tmp/template2.yml >> docker-compose.yml
  ```
  or, better, use `envsubst` / a real template engine and inject the key as a
  properly-quoted YAML string.
- **`template1.yml` and `docker-compose-template.yml` diverge**
  (`janpdevops/...:latest` vs `janpdev/...:v0.1`). Only one is actually used (the
  split templates). Either delete `docker-compose-template.yml` or make it
  authoritative and generate from it.
- **`template2.yml` still has hard-coded Windows paths** for `/config` and `/data`.
  These will be baked into whatever server compose is generated — meaning the
  generated file is only useful on that one Windows machine. Parameterize them:
  ```yaml
  - #SERVER_CONFIG_DIR#:/config
  - #SERVER_DATA_DIR#:/data
  ```
- **`template2.yml` has no trailing-newline handling either.** Same risk.
- **`#USER_NAME` on line 14 of `docker-compose-template.yml`** is missing its
  trailing `#` → `sed` will never replace it. Bug in the (currently unused)
  template.
- **`version: "2.1"`** is obsolete.

---

## 7. `client/scripts/adduser-template.sh`

```bash
adduser --uid ${UID} --gid 2000 --disabled-password --disabled-login ${username}
```

- **`${UID}` is a bash builtin** — it always holds the current shell's UID, so this
  line silently ignores whatever you meant to pass in. Rename to something like
  `${NEW_UID}`.
- **`${username}` (lowercase)** is not exported by convention. If this ever gets
  sourced or called with env vars, use `${USERNAME}`. Also, on many Linux distros
  `USERNAME` is set by `login` — pick a non-colliding name like `RSYNC_USERNAME`.
- `adduser --disabled-password --disabled-login` is Debian-specific.
  `linuxserver/openssh-server` is based on **Alpine**, whose `adduser` uses
  different flags (`-D`, `-H`, etc.). This template will not run against the base
  image the server actually uses.
- The script is a stub (`# TODO: find non-interactive version`). Alpine equivalent:
  ```sh
  addgroup -g 2000 backupusers 2>/dev/null || true
  adduser -D -H -u "$NEW_UID" -G backupusers "$RSYNC_USERNAME"
  ```

This template is not wired into anything yet, but it should either be finished or
removed to reduce confusion.

---

## 8. Cross-cutting concerns

### Security

1. **The client's SSH key can do arbitrary things over SSH**, not just rsync. That
   means a compromised client can `ssh` in and delete anything under `/data` —
   which is the whole backup mirror. Restrict via `authorized_keys` options:
   ```
   command="rrsync -wo /data",restrict ssh-ed25519 AAAA...
   ```
   `rrsync` (ships with rsync) enforces read-only or write-only rsync-only access.
   This is the single most impactful hardening step for the mirror.
2. **No host-key verification on first run.** `StrictHostKeyChecking=no` opens the
   door to MITM until `.ssh/known_hosts` is written. Provide a way to seed the
   server host key out-of-band, or at least document the risk clearly.
3. **Private key on a Windows bind-mount** has whatever ACLs Windows gives it —
   often world-readable within the user profile. OpenSSH inside Linux does *not*
   refuse it because the mount masks permissions. Document that the key mount must
   be a directory only the user can read.
4. **No key-rotation story.** How does a user replace a compromised key? Not
   addressed.
5. **No logging / audit trail** on either side.

### Portability

- The whole system assumes Docker Desktop on Windows (bind-mount syntax like
  `C:\nobackup\...`). Nothing in the compose files exercises Linux/macOS paths.
  Provide **at least one Linux example** (`./data:/data`) in `docker-compose.yml`
  or in `docs/`.

### Repository hygiene

- **No `.gitignore`.** `.idea/`, `.obsidian/`, and — worse — any generated
  `ssh_key` / `ssh_key.pub` that ends up next to the source tree can be
  accidentally committed. Add:
  ```
  .idea/
  .obsidian/
  ssh_key
  ssh_key.pub
  public/
  known_hosts
  .env
  ```
- **No `.dockerignore`.** Same problem for the build context.
- **`Rsync-Backup.md`** as the filename is unusual — GitHub renders `README.md` on
  the repo landing page. Rename to `README.md` or add a small `README.md` that
  links to both `Rsync-Backup.md` and `Backup-overview.md`.
- **No LICENSE header info in the README.** You have a `LICENSE` file but the
  README doesn't state which license.
- **Version numbers**: `v0.1` in Dockerfiles, `v0.11` in the client compose,
  `latest` in `template1.yml`. Pick one strategy and enforce it.
- **CI**: no GitHub Actions to at least `docker build` both images on push. A
  one-file workflow would catch a lot of the above.

### Testing

- No integration test that spins up server + client, runs a sync, and verifies
  content on the server side. Given this is a backup tool, an automated round-trip
  test (sync → tamper → resync → assert) is essential before you can drop the
  "don't use it yet!" warning.

---

## Prioritized action list

### Must-fix before publishing to GitHub

1. Remove personal Windows paths and hard-coded IPs from all `docker-compose.yml`;
   move to `.env` + `.env.example`.
2. Add `.gitignore` and `.dockerignore`.
3. Add `set -euo pipefail` and input validation to `rsync2backup.sh`.
4. Fix the `template1.yml` + public-key concatenation to guarantee correct YAML
   (strip trailing newline).
5. Standardize image versions across README, Dockerfiles, and compose files.
6. Rename `Rsync-Backup.md` → `README.md` (or add a `README.md` landing page).
7. State the license in the README.

### Should-fix soon

8. Restrict the client key on the server via `authorized_keys`
   `command="rrsync -wo /data",restrict`.
9. Fix rsync trailing-slash semantics and the `--delete` asymmetry; document push
   vs pull semantics.
10. Add explicit `known_hosts` handling; document TOFU risk.
11. Parameterize `template2.yml` server paths and fix the missing `#` on
    `#USER_NAME` in `docker-compose-template.yml`.
12. Rewrite `adduser-template.sh` for Alpine, or delete it.
13. Add a minimal GitHub Actions workflow that builds both images.
14. Pin `linuxserver/openssh-server` to a specific tag (not `:latest`).

### Nice-to-have

15. Add `--partial`, `--bwlimit`, dry-run, and structured logging options via env
    vars.
16. Add an integration test (docker-compose network with both containers, verify a
    file round-trips).
17. Add `HEALTHCHECK` to the server image.
18. Bind the server port to a specific interface, not `0.0.0.0`.
19. Squash the three `dos2unix` layers in the client Dockerfile.

---

## Next steps

A natural first batch of implementation work is:

- `.gitignore`
- `.dockerignore`
- `.env.example` + `.env`-based compose files (client & server)
- hardened `rsync2backup.sh` (strict mode, input validation, safer sed, correct
  trailing slashes, symmetric `known_hosts` handling)
- corrected templates (`template1.yml` newline handling, parameterized paths)
- consistent image versioning

These can be done without changing the fundamental architecture, and would move
the project from "prototype" to "safe to try on real data" — at which point stages
2–4 of the backup pipeline (see `Backup-overview.md`) become the next focus.

