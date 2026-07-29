<#
.SYNOPSIS
    End-to-end integration test for rsync2backup (client <-> server).

.DESCRIPTION
    Builds both images, spins up an isolated docker network, starts the server
    with an empty data directory and runs the client through two sync passes:

      Pass 1 (initial):
        Client source contains: hello.txt, subdir/nested.txt, todelete.me
        Expectation: all three files appear on the server.

      Pass 2 (mutation):
        Client source now contains: hello.txt, subdir/nested.txt, add
        (todelete.me removed, "add" added)
        Expectation: "add" appears on the server, todelete.me is gone,
                     hello.txt is still present.

    Cleans up containers, network and scratch directories on completion
    (unless -KeepScratch is passed).

.PARAMETER SkipBuild
    Skip docker image builds (use existing local images).

.PARAMETER KeepScratch
    Do not delete the scratch working directory on exit
    (useful for debugging failures).

.EXAMPLE
    ./run-test.ps1
    ./run-test.ps1 -SkipBuild
    ./run-test.ps1 -KeepScratch
#>
[CmdletBinding()]
param(
    [switch]$SkipBuild,
    [switch]$KeepScratch
)

$ErrorActionPreference = 'Continue'   # native docker stderr must not throw
Set-StrictMode -Version Latest

# ----------------------------------------------------------------------------
# Paths & names
# ----------------------------------------------------------------------------
$here     = Split-Path -Parent $PSCommandPath
$repoRoot = (Resolve-Path (Join-Path $here '..\..')).Path
$fixtures = Join-Path $here 'fixtures'

$runId    = Get-Date -Format 'yyyyMMdd-HHmmss'
$scratch  = Join-Path $env:TEMP "rsync2backup-test-$runId"
$network  = "rsync2backup-test-net-$runId"
$server   = "rsync2backup-test-server-$runId"

$commonImage = 'janpdev/rsyncbackup-common:v0.1'   # tag hard-coded in client/Dockerfile FROM
$clientImage = 'rsync2backup-client:test'

# ----------------------------------------------------------------------------
# Helpers
# ----------------------------------------------------------------------------
function Info($m) { Write-Host "==> $m" -ForegroundColor Cyan }
function Ok($m)   { Write-Host "OK   $m" -ForegroundColor Green }
function Fail($m) { Write-Host "FAIL $m" -ForegroundColor Red; throw $m }

function Ensure-Dir($p) { [void](New-Item -ItemType Directory -Force -Path $p -ErrorAction Stop) }

function Assert-ExitZero($label) {
    if ($LASTEXITCODE -ne 0) { Fail "$label (exit=$LASTEXITCODE)" }
}

function Assert-FileExists($path, $label) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        Fail "$label : expected file missing: $path"
    }
    Ok "$label"
}

function Assert-FileMissing($path, $label) {
    if (Test-Path -LiteralPath $path) {
        Fail "$label : file should be gone but is present: $path"
    }
    Ok "$label"
}

# Wait until a TCP port answers inside the docker network.
# Native docker output on stderr can trip $ErrorActionPreference='Stop' in
# Windows PowerShell, so we merge stderr into stdout and swallow it.
function Wait-ForSsh($host_, $port, $timeoutSec = 30) {
    $probeImage = 'alpine:3.20'

    # Pre-pull so the wait loop itself never causes an image pull
    # (whose progress lines go to stderr and confuse Windows PowerShell).
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        docker image inspect $probeImage *>$null
        if ($LASTEXITCODE -ne 0) {
            Info "Pulling probe image: $probeImage"
            docker pull $probeImage *>&1 | Out-Null
            if ($LASTEXITCODE -ne 0) { Fail "docker pull $probeImage failed" }
        }

        $deadline = (Get-Date).AddSeconds($timeoutSec)
        while ((Get-Date) -lt $deadline) {
            $probe = docker run --rm --network $network $probeImage `
                sh -c "nc -z -w 1 $host_ $port && echo up" 2>&1
            if ("$probe" -match 'up') { return }
            Start-Sleep -Milliseconds 500
        }
    } finally {
        $ErrorActionPreference = $prev
    }
    Fail "SSH did not come up on ${host_}:${port} within ${timeoutSec}s"
}

# Run the client container with common env / mounts. Extra args go to `docker run`.
function Invoke-Client([string]$label, [string[]]$extraDockerArgs = @()) {
    Info $label
    $dockerArgs = @(
        'run', '--rm'
    ) + $extraDockerArgs + @(
        '-e', "RSYNC_SERVER=$server",
        '-e', 'RSYNC_PORT=2222',
        '-e', 'USER_NAME=transfer',
        '-e', 'RSYNC_UID=1000',
        '-e', 'RSYNC_GID=1000',
        '-e', 'PUSH=1',
        '-v', "${clientKeys}:/data/sshkeys",
        '-v', "${clientSource}:/upload",
        $clientImage
    )
    & docker @dockerArgs
    Assert-ExitZero $label
}

# ----------------------------------------------------------------------------
# Main
# ----------------------------------------------------------------------------
try {
    # -- Build images -------------------------------------------------------
    if (-not $SkipBuild) {
        Info "Building server image: $commonImage"
        docker build -q -t $commonImage (Join-Path $repoRoot 'server') | Out-Null
        Assert-ExitZero "docker build server"

        Info "Building client image: $clientImage"
        docker build -q -t $clientImage (Join-Path $repoRoot 'client') | Out-Null
        Assert-ExitZero "docker build client"
    } else {
        Info "Skipping image builds (-SkipBuild)"
    }

    # -- Scratch dirs -------------------------------------------------------
    Info "Scratch dir: $scratch"
    $clientKeys   = Join-Path $scratch 'client-keys'
    $clientSource = Join-Path $scratch 'client-source'
    $serverConfig = Join-Path $scratch 'server-config'
    $serverData   = Join-Path $scratch 'server-data'
    $serverKeys   = Join-Path $scratch 'server-keys'
    foreach ($d in @($clientKeys, $clientSource, $serverConfig, $serverData, $serverKeys)) {
        Ensure-Dir $d
    }

    Info "Populating client source from fixtures"
    Copy-Item -Recurse -Force -Path (Join-Path $fixtures '*') -Destination $clientSource -ErrorAction Stop
    Assert-FileExists (Join-Path $clientSource 'todelete.me') "fixture todelete.me present in client source"

    # -- Docker network -----------------------------------------------------
    Info "Creating docker network: $network"
    docker network create $network | Out-Null
    Assert-ExitZero "docker network create"

    # -- Client run #1: key generation only (no sync) -----------------------
    # First run of rsync2backup.sh detects missing ssh_key, generates a keypair
    # and a server docker-compose.yml, then exits WITHOUT running rsync.
    Invoke-Client 'Client run #1 -- key generation'
    Assert-FileExists (Join-Path $clientKeys 'ssh_key')            "private key generated"
    Assert-FileExists (Join-Path $clientKeys 'public/ssh_key.pub') "public key generated"

    # -- Give the server the public key BEFORE starting it ------------------
    # The linuxserver/openssh-server image installs keys from PUBLIC_KEY_DIR
    # only during container startup.
    Copy-Item -Force -Path (Join-Path $clientKeys 'public/ssh_key.pub') -Destination $serverKeys -ErrorAction Stop

    # -- Start the server ---------------------------------------------------
    Info "Starting server container: $server"
    docker run -d --rm `
        --name $server `
        --network $network `
        -e PUID=1000 -e PGID=1000 -e TZ=Etc/UTC `
        -e PUBLIC_KEY_DIR=/keys `
        -e SUDO_ACCESS=false `
        -e USER_NAME=transfer `
        -v "${serverConfig}:/config" `
        -v "${serverData}:/data" `
        -v "${serverKeys}:/keys" `
        $commonImage | Out-Null
    Assert-ExitZero "docker run server"

    Wait-ForSsh $server 2222 45

    # Make sure /data is writable by the transfer user (harmless on Windows
    # bind mounts, required on Linux bind mounts).
    docker exec $server sh -c 'mkdir -p /data && chown -R transfer:transfer /data' | Out-Null
    Assert-ExitZero "chown /data"

    # -- Client run #2: initial sync ---------------------------------------
    Invoke-Client 'Client run #2 -- initial push' @('--network', $network)

    # Verify: rsync source `/upload/` (with trailing slash) is transferred into
    # `/data/` (with trailing slash), giving `/data/...` on the server
    # (not `/data/upload/...` like the old behavior).
    $syncedRoot = Join-Path $serverData ''
    Info "Verifying initial sync in: $syncedRoot"
    Assert-FileExists (Join-Path $syncedRoot 'hello.txt')          "hello.txt on server"
    Assert-FileExists (Join-Path $syncedRoot 'subdir\nested.txt')  "subdir/nested.txt on server"
    Assert-FileExists (Join-Path $syncedRoot 'todelete.me')        "todelete.me on server"

    # -- Mutate client -----------------------------------------------------
    Info "Mutating client source: remove todelete.me, add 'add'"
    Remove-Item -LiteralPath (Join-Path $clientSource 'todelete.me') -Force -ErrorAction Stop
    Set-Content -LiteralPath (Join-Path $clientSource 'add') -Value 'added on second sync run' -NoNewline -ErrorAction Stop

    # -- Client run #3: mutation sync --------------------------------------
    Invoke-Client 'Client run #3 -- mutation push' @('--network', $network)

    # Verify: `add` present, `todelete.me` gone, other files untouched.
    Info "Verifying mutation sync in: $syncedRoot"
    Assert-FileExists  (Join-Path $syncedRoot 'add')                "add on server"
    Assert-FileMissing (Join-Path $syncedRoot 'todelete.me')        "todelete.me removed on server"
    Assert-FileExists  (Join-Path $syncedRoot 'hello.txt')          "hello.txt still on server"
    Assert-FileExists  (Join-Path $syncedRoot 'subdir\nested.txt')  "subdir/nested.txt still on server"

    Write-Host ""
    Write-Host "ALL CHECKS PASSED" -ForegroundColor Green
    Write-Host ""
}
finally {
    Info "Cleanup"
    # Stop the server (started with --rm, so removing implicitly).
    # `2>&1 | Out-Null` avoids stderr-as-error under Windows PowerShell
    # when the container/network is already gone.
    docker rm -f $server 2>&1 | Out-Null
    docker network rm $network 2>&1 | Out-Null

    if ($KeepScratch) {
        Write-Host "Scratch preserved at: $scratch" -ForegroundColor Yellow
    } elseif (Test-Path -LiteralPath $scratch) {
        try { Remove-Item -Recurse -Force -LiteralPath $scratch } catch { }
    }
}

