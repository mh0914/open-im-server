[CmdletBinding()]
param(
    [ValidateSet("monolith", "services", "all")]
    [string]$Mode = "monolith",
    [string]$Registry = "local",
    [string]$Tag = "dev",
    [string[]]$ServiceNames,
    [switch]$Push,
    [switch]$SaveTar,
    [string]$TarDir = "artifacts/docker"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Get-ImageRef {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Registry,
        [Parameter(Mandatory = $true)][string]$Tag
    )

    if ([string]::IsNullOrWhiteSpace($Registry)) {
        return "${Name}:${Tag}"
    }

    return "${Registry}/${Name}:${Tag}"
}

function Invoke-Docker {
    param([Parameter(Mandatory = $true)][string[]]$Args)

    & docker @Args
    if ($LASTEXITCODE -ne 0) {
        throw "docker $($Args -join ' ') failed with exit code $LASTEXITCODE"
    }
}

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$ResolvedTarDir = if ([System.IO.Path]::IsPathRooted($TarDir)) { $TarDir } else { Join-Path $RepoRoot $TarDir }

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    throw "Docker CLI not found. Install Docker Desktop or Docker Engine first."
}

$definitions = @(
    @{
        Name = "openim-server"
        Dockerfile = "Dockerfile"
        Category = "monolith"
    },
    @{
        Name = "openim-api"
        Dockerfile = "build/images/openim-api/Dockerfile"
        Category = "services"
    },
    @{
        Name = "openim-crontask"
        Dockerfile = "build/images/openim-crontask/Dockerfile"
        Category = "services"
    },
    @{
        Name = "openim-msggateway"
        Dockerfile = "build/images/openim-msggateway/Dockerfile"
        Category = "services"
    },
    @{
        Name = "openim-msgtransfer"
        Dockerfile = "build/images/openim-msgtransfer/Dockerfile"
        Category = "services"
    },
    @{
        Name = "openim-push"
        Dockerfile = "build/images/openim-push/Dockerfile"
        Category = "services"
    },
    @{
        Name = "openim-rpc-auth"
        Dockerfile = "build/images/openim-rpc-auth/Dockerfile"
        Category = "services"
    },
    @{
        Name = "openim-rpc-conversation"
        Dockerfile = "build/images/openim-rpc-conversation/Dockerfile"
        Category = "services"
    },
    @{
        Name = "openim-rpc-friend"
        Dockerfile = "build/images/openim-rpc-friend/Dockerfile"
        Category = "services"
    },
    @{
        Name = "openim-rpc-group"
        Dockerfile = "build/images/openim-rpc-group/Dockerfile"
        Category = "services"
    },
    @{
        Name = "openim-rpc-msg"
        Dockerfile = "build/images/openim-rpc-msg/Dockerfile"
        Category = "services"
    },
    @{
        Name = "openim-rpc-third"
        Dockerfile = "build/images/openim-rpc-third/Dockerfile"
        Category = "services"
    },
    @{
        Name = "openim-rpc-user"
        Dockerfile = "build/images/openim-rpc-user/Dockerfile"
        Category = "services"
    }
)

$selected = switch ($Mode) {
    "monolith" { $definitions | Where-Object { $_.Category -eq "monolith" } }
    "services" { $definitions | Where-Object { $_.Category -eq "services" } }
    "all"      { $definitions }
}

if ($ServiceNames -and $ServiceNames.Count -gt 0) {
    $selected = $selected | Where-Object { $_.Name -in $ServiceNames }
}

if (-not $selected -or $selected.Count -eq 0) {
    throw "No Docker images selected to build."
}

if ($SaveTar) {
    New-Item -ItemType Directory -Force -Path $ResolvedTarDir | Out-Null
}

foreach ($definition in $selected) {
    $imageRef = Get-ImageRef -Name $definition.Name -Registry $Registry -Tag $Tag
    $dockerfilePath = Join-Path $RepoRoot $definition.Dockerfile

    Write-Host "Building $imageRef"
    Invoke-Docker -Args @(
        "build",
        "--file", $dockerfilePath,
        "--tag", $imageRef,
        $RepoRoot
    )

    if ($Push) {
        Write-Host "Pushing $imageRef"
        Invoke-Docker -Args @("push", $imageRef)
    }

    if ($SaveTar) {
        $tarPath = Join-Path $ResolvedTarDir ("{0}-{1}.tar" -f $definition.Name, $Tag)
        Write-Host "Saving $imageRef to $tarPath"
        Invoke-Docker -Args @("save", "--output", $tarPath, $imageRef)
    }
}

Write-Host ""
Write-Host "Docker build completed."
