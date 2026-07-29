#!/bin/bash
set -euo pipefail

# =============================================================================
# rsync2backup.sh — client-side sync orchestrator
#
# On first run: generates SSH keypair and server docker-compose template
# On subsequent runs: syncs /upload to remote server via rsync over SSH
# =============================================================================

# Validate required environment variables
declare -A required_vars=(
	[RSYNC_SERVER]="IP or hostname of backup server"
	[RSYNC_PORT]="SSH port on server"
	[USER_NAME]="SSH username on server"
	[RSYNC_UID]="numeric UID for server user"
	[RSYNC_GID]="numeric GID for server user"
	[PUSH]="1 for push mode (default), 0 for pull mode"
)

for var in "${!required_vars[@]}"; do
	if [[ -z "${!var:-}" ]]; then
		echo "ERROR: Required env var '$var' not set (${required_vars[$var]})" >&2
		exit 1
	fi
done

# Ensure we're in the sshkeys directory (where keys are mounted)
cd /data/sshkeys

# =============================================================================
# First run: key generation and server compose template generation
# =============================================================================
if [[ ! -f ssh_key ]]; then
	echo "==> First run detected: generating SSH keypair and server template..."
	echo "==> Creating keypairs..."
	ssh-keygen -t ed25519 -f ssh_key -N "" -C "rsync2backup"

	mkdir -p public
	# Explicit move of the public key file (not a glob)
	mv ssh_key.pub public/ssh_key.pub

	echo "==> Key pair created successfully"
	echo "==> Generating server docker-compose.yml from template..."

	# Concatenate templates with public key.
	# Use printf to strip any trailing newline from template1, so the key lands on the same line.
	{
		printf '%s' "$(cat /tmp/template1.yml)"
		cat public/ssh_key.pub
		echo ""
		cat /tmp/template2.yml
	} > docker-compose.yml

	# Use pipe delimiter for sed to avoid issues if values contain /
	sed -i "s|#RSYNC_PORT#|${RSYNC_PORT}|g" "docker-compose.yml"
	sed -i "s|#USER_NAME#|${USER_NAME}|g" "docker-compose.yml"
	sed -i "s|#RSYNC_UID#|${RSYNC_UID}|g" "docker-compose.yml"
	sed -i "s|#RSYNC_GID#|${RSYNC_GID}|g" "docker-compose.yml"

	# Server paths are optional; if not set, use defaults
	SERVER_CONFIG_DIR="${SERVER_CONFIG_DIR:-/data/config}"
	SERVER_DATA_DIR="${SERVER_DATA_DIR:-/data/transfer_target}"
	sed -i "s|#SERVER_CONFIG_DIR#|${SERVER_CONFIG_DIR}|g" "docker-compose.yml"
	sed -i "s|#SERVER_DATA_DIR#|${SERVER_DATA_DIR}|g" "docker-compose.yml"

	echo ""
	echo "==> SUCCESS: SSH keypair and server template generated."
	echo "==> Next steps:"
	echo "    1. Copy 'public/ssh_key.pub' to your backup server"
	echo "    2. Start the server with the generated docker-compose.yml"
	echo "    3. Run this script again to perform the initial sync"
	exit 0
fi

# =============================================================================
# Subsequent runs: perform rsync sync
# =============================================================================
echo "==> Starting rsync sync..."

# Determine strict host checking based on known_hosts presence
STRICT_HOST_CHECKING="no"
if [[ -d .ssh && -f .ssh/known_hosts ]]; then
	# Restore persisted .ssh (contains known_hosts from previous runs)
	cp -r .ssh "$HOME/.ssh" || {
		echo "WARNING: Failed to restore .ssh from persistent storage" >&2
	}
	STRICT_HOST_CHECKING="yes"
	echo "==> Using saved known_hosts (StrictHostKeyChecking=yes)"
else
	echo "==> WARNING: No known_hosts found; first connection will not be verified against known hosts" >&2
fi

# Convert PUSH to numeric (default to push mode)
PUSH="${PUSH:-1}"
if [[ ! "${PUSH}" =~ ^[0-9]+$ ]]; then
	echo "ERROR: PUSH must be numeric (1 or 0), got '${PUSH}'" >&2
	exit 1
fi

# Build SSH options
SSH_OPTS=(
	"-i" "/data/sshkeys/ssh_key"
	"-o" "StrictHostKeyChecking=${STRICT_HOST_CHECKING}"
	"-p" "${RSYNC_PORT}"
)

if (( PUSH > 0 )); then
	echo "==> Push mode: uploading /upload/ to ${USER_NAME}@${RSYNC_SERVER}:/data/"
	rsync -av --delete \
		-e "ssh ${SSH_OPTS[*]}" \
		/upload/ \
		"${USER_NAME}@${RSYNC_SERVER}:/data/"

	# Persist the updated .ssh (includes any new host keys added)
	if [[ -d "$HOME/.ssh" ]]; then
		cp -r "$HOME/.ssh" . || {
			echo "WARNING: Failed to persist .ssh to storage" >&2
		}
	fi
else
	echo "==> Pull mode: downloading ${USER_NAME}@${RSYNC_SERVER}:/data/ to /upload/"
	rsync -av \
		-e "ssh ${SSH_OPTS[*]}" \
		"${USER_NAME}@${RSYNC_SERVER}:/data/" \
		/upload/

	# Persist the updated .ssh (includes any new host keys added)
	if [[ -d "$HOME/.ssh" ]]; then
		cp -r "$HOME/.ssh" . || {
			echo "WARNING: Failed to persist .ssh to storage" >&2
		}
	fi
fi

echo "==> Sync completed successfully"
