[CmdletBinding()]
param(
    [string]$EnvFile = "deployments/docker/.env",
    [string]$SourceDir = "config",
    [string]$OutputDir = "deployments/docker/config"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Resolve-RepoPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return $Path
    }

    return Join-Path $script:RepoRoot $Path
}

function Read-EnvFile {
    param([Parameter(Mandatory = $true)][string]$Path)

    $values = @{}
    if (-not (Test-Path -LiteralPath $Path)) {
        return $values
    }

    foreach ($line in Get-Content -LiteralPath $Path) {
        $trimmed = $line.Trim()
        if (-not $trimmed -or $trimmed.StartsWith("#")) {
            continue
        }

        $parts = $trimmed -split "=", 2
        if ($parts.Count -ne 2) {
            continue
        }

        $key = $parts[0].Trim()
        $value = $parts[1].Trim()

        if (
            $value.Length -ge 2 -and
            (
                ($value.StartsWith('"') -and $value.EndsWith('"')) -or
                ($value.StartsWith("'") -and $value.EndsWith("'"))
            )
        ) {
            $value = $value.Substring(1, $value.Length - 2)
        }

        $values[$key] = $value
    }

    return $values
}

function Set-ConfigValue {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string[]]$Pairs
    )

    $content = Get-Content -LiteralPath $Path -Raw
    for ($i = 0; $i -lt $Pairs.Count; $i += 2) {
        $content = $content.Replace($Pairs[$i], $Pairs[$i + 1])
    }
    Set-Content -LiteralPath $Path -Value $content -Encoding UTF8
}

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$ResolvedEnvFile = Resolve-RepoPath -Path $EnvFile
$ResolvedSourceDir = Resolve-RepoPath -Path $SourceDir
$ResolvedOutputDir = Resolve-RepoPath -Path $OutputDir

if (-not (Test-Path -LiteralPath $ResolvedSourceDir)) {
    throw "Source config directory not found: $ResolvedSourceDir"
}

$defaults = @{
    MONGO_ADDRESS           = "mongo:27017"
    MONGO_DATABASE          = "openim_v3"
    MONGO_USERNAME          = "openIM"
    MONGO_PASSWORD          = "openIM123"
    REDIS_ADDRESS           = "redis:6379"
    REDIS_PASSWORD          = "openIM123"
    KAFKA_ADDRESS           = "kafka:9092"
    KAFKA_USERNAME          = ""
    KAFKA_PASSWORD          = ""
    ETCD_ADDRESS            = "etcd:2379"
    ETCD_USERNAME           = ""
    ETCD_PASSWORD           = ""
    MINIO_INTERNAL_ADDRESS  = "minio:9000"
    MINIO_EXTERNAL_ADDRESS  = "http://127.0.0.1:10005"
    MINIO_ACCESS_KEY_ID     = "root"
    MINIO_SECRET_ACCESS_KEY = "openIM123"
    OPENIM_SECRET           = "openIM123"
    LOG_IS_STDOUT           = "true"
    LOG_LEVEL               = "3"
}

$envValues = Read-EnvFile -Path $ResolvedEnvFile
foreach ($entry in $envValues.GetEnumerator()) {
    $defaults[$entry.Key] = $entry.Value
}

New-Item -ItemType Directory -Force -Path $ResolvedOutputDir | Out-Null
Copy-Item -Path (Join-Path $ResolvedSourceDir "*") -Destination $ResolvedOutputDir -Recurse -Force

Set-ConfigValue -Path (Join-Path $ResolvedOutputDir "discovery.yml") -Pairs @(
    "address: [localhost:12379]", "address: [$($defaults.ETCD_ADDRESS)]",
    "username:", "username: $($defaults.ETCD_USERNAME)",
    "password:", "password: $($defaults.ETCD_PASSWORD)"
)

Set-ConfigValue -Path (Join-Path $ResolvedOutputDir "kafka.yml") -Pairs @(
    "address: [localhost:19094]", "address: [$($defaults.KAFKA_ADDRESS)]",
    "username:", "username: $($defaults.KAFKA_USERNAME)",
    "password:", "password: $($defaults.KAFKA_PASSWORD)"
)

Set-ConfigValue -Path (Join-Path $ResolvedOutputDir "mongodb.yml") -Pairs @(
    "address: [localhost:37017]", "address: [$($defaults.MONGO_ADDRESS)]",
    "database: openim_v3", "database: $($defaults.MONGO_DATABASE)",
    "username: openIM", "username: $($defaults.MONGO_USERNAME)",
    "password: openIM123", "password: $($defaults.MONGO_PASSWORD)",
    "authSource: openim_v3", "authSource: $($defaults.MONGO_DATABASE)",
    "hosts: [127.0.0.1:37017, 127.0.0.1:37018, 127.0.0.1:37019]", "hosts: [$($defaults.MONGO_ADDRESS)]"
)

Set-ConfigValue -Path (Join-Path $ResolvedOutputDir "redis.yml") -Pairs @(
    "address: [localhost:16379]", "address: [$($defaults.REDIS_ADDRESS)]",
    "password: openIM123", "password: $($defaults.REDIS_PASSWORD)"
)

Set-ConfigValue -Path (Join-Path $ResolvedOutputDir "minio.yml") -Pairs @(
    "accessKeyID: root", "accessKeyID: $($defaults.MINIO_ACCESS_KEY_ID)",
    "secretAccessKey: openIM123", "secretAccessKey: $($defaults.MINIO_SECRET_ACCESS_KEY)",
    "internalAddress: localhost:10005", "internalAddress: $($defaults.MINIO_INTERNAL_ADDRESS)",
    "externalAddress: http://external_ip:10005", "externalAddress: $($defaults.MINIO_EXTERNAL_ADDRESS)"
)

Set-ConfigValue -Path (Join-Path $ResolvedOutputDir "share.yml") -Pairs @(
    "secret: openIM123", "secret: $($defaults.OPENIM_SECRET)"
)

Set-ConfigValue -Path (Join-Path $ResolvedOutputDir "log.yml") -Pairs @(
    "isStdout: false", "isStdout: $($defaults.LOG_IS_STDOUT.ToLowerInvariant())",
    "remainLogLevel: 6", "remainLogLevel: $($defaults.LOG_LEVEL)"
)

Write-Host "Docker config prepared in $ResolvedOutputDir"
Write-Host "Applied addresses:"
Write-Host "  MongoDB: $($defaults.MONGO_ADDRESS)"
Write-Host "  Redis:   $($defaults.REDIS_ADDRESS)"
Write-Host "  etcd:    $($defaults.ETCD_ADDRESS)"
Write-Host "  Kafka:   $($defaults.KAFKA_ADDRESS)"
Write-Host "  MinIO:   $($defaults.MINIO_INTERNAL_ADDRESS)"
