[CmdletBinding()]
param(
    [string]$EnvFile = "deployments/docker/.env",
    [string]$ShareConfig = "deployments/docker/config/share.yml",
    [string]$ApiBaseUrl,
    [string]$Secret,
    [string]$AdminUserID,
    [int]$PlatformID = 2,
    [string[]]$UserIDs = @("demo_user_001", "demo_user_002")
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

function Get-FirstAdminUserIDFromShareConfig {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }

    $content = Get-Content -LiteralPath $Path -Raw
    $match = [regex]::Match($content, "userIDs:\s*\[(?<ids>[^\]]+)\]")
    if (-not $match.Success) {
        return $null
    }

    $first = $match.Groups["ids"].Value.Split(",")[0].Trim()
    if ($first.Length -eq 0) {
        return $null
    }

    return $first
}

function New-OperationID {
    param([Parameter(Mandatory = $true)][string]$Prefix)

    $suffix = [Guid]::NewGuid().ToString("N").Substring(0, 8)
    return "$Prefix-$suffix"
}

function Invoke-OpenIMApi {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][object]$Body,
        [hashtable]$Headers = @{}
    )

    $requestHeaders = @{
        operationID = New-OperationID -Prefix "openim"
    }

    foreach ($entry in $Headers.GetEnumerator()) {
        $requestHeaders[$entry.Key] = [string]$entry.Value
    }

    $uri = "{0}{1}" -f $script:ResolvedApiBaseUrl.TrimEnd("/"), $Path
    $jsonBody = $Body | ConvertTo-Json -Depth 20
    $response = Invoke-RestMethod -Method Post -Uri $uri -Headers $requestHeaders -ContentType "application/json" -Body $jsonBody

    if ($null -eq $response) {
        throw "API $Path returned an empty response."
    }

    if ($response.errCode -ne 0) {
        throw "API $Path failed: [$($response.errCode)] $($response.errMsg) $($response.errDlt)"
    }

    return $response
}

function Get-AdminToken {
    $resp = Invoke-OpenIMApi -Path "/auth/get_admin_token" -Body @{
        secret = $script:ResolvedSecret
        userID = $script:ResolvedAdminUserID
    }

    return $resp.data.token
}

function Get-MissingUserIDs {
    param([Parameter(Mandatory = $true)][string]$AdminToken)

    $resp = Invoke-OpenIMApi -Path "/user/account_check" -Headers @{ token = $AdminToken } -Body @{
        checkUserIDs = $script:ResolvedUserIDs
    }

    $missing = New-Object System.Collections.Generic.List[string]
    foreach ($result in $resp.data.results) {
        if ($result.accountStatus -ne 1) {
            $missing.Add([string]$result.userID)
        }
    }

    return $missing.ToArray()
}

function Register-Users {
    param(
        [Parameter(Mandatory = $true)][string]$AdminToken,
        [Parameter(Mandatory = $true)][string[]]$UserIDsToRegister
    )

    if (-not $UserIDsToRegister -or $UserIDsToRegister.Count -eq 0) {
        return
    }

    $users = foreach ($userID in $UserIDsToRegister) {
        @{
            userID = $userID
            nickname = $userID
        }
    }

    [void](Invoke-OpenIMApi -Path "/user/user_register" -Headers @{ token = $AdminToken } -Body @{
        users = $users
    })
}

function Get-UserToken {
    param(
        [Parameter(Mandatory = $true)][string]$AdminToken,
        [Parameter(Mandatory = $true)][string]$UserID,
        [Parameter(Mandatory = $true)][int]$PlatformID
    )

    $resp = Invoke-OpenIMApi -Path "/auth/get_user_token" -Headers @{ token = $AdminToken } -Body @{
        userID = $UserID
        platformID = $PlatformID
    }

    return $resp.data.token
}

$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$ResolvedEnvFile = Resolve-RepoPath -Path $EnvFile
$ResolvedShareConfig = Resolve-RepoPath -Path $ShareConfig
$envValues = Read-EnvFile -Path $ResolvedEnvFile

$defaultApiPort = if ($envValues.ContainsKey("OPENIM_API_PORT")) { $envValues["OPENIM_API_PORT"] } else { "10002" }
$defaultMsgGatewayPort = if ($envValues.ContainsKey("OPENIM_MSG_GATEWAY_PORT")) { $envValues["OPENIM_MSG_GATEWAY_PORT"] } else { "10001" }
$defaultMinioConsolePort = if ($envValues.ContainsKey("MINIO_CONSOLE_PORT")) { $envValues["MINIO_CONSOLE_PORT"] } else { "10004" }
$defaultSecret = if ($envValues.ContainsKey("OPENIM_SECRET")) { $envValues["OPENIM_SECRET"] } else { "openIM123" }
$defaultAdminUserID = Get-FirstAdminUserIDFromShareConfig -Path $ResolvedShareConfig
if ([string]::IsNullOrWhiteSpace($defaultAdminUserID)) {
    $defaultAdminUserID = "imAdmin"
}

$ResolvedApiBaseUrl = if ([string]::IsNullOrWhiteSpace($ApiBaseUrl)) { "http://127.0.0.1:$defaultApiPort" } else { $ApiBaseUrl.TrimEnd("/") }
$ResolvedSecret = if ([string]::IsNullOrWhiteSpace($Secret)) { $defaultSecret } else { $Secret }
$ResolvedAdminUserID = if ([string]::IsNullOrWhiteSpace($AdminUserID)) { $defaultAdminUserID } else { $AdminUserID }
$ResolvedUserIDs = $UserIDs

if (-not $ResolvedUserIDs -or $ResolvedUserIDs.Count -eq 0) {
    throw "At least one userID must be provided."
}

Write-Host "OpenIM API: $ResolvedApiBaseUrl"
Write-Host "Admin userID: $ResolvedAdminUserID"
Write-Host "User platformID: $PlatformID"
Write-Host ""

$adminToken = Get-AdminToken
$missingUserIDs = Get-MissingUserIDs -AdminToken $adminToken
if ($null -eq $missingUserIDs) {
    $missingUserIDs = @()
}
if ($missingUserIDs.Count -gt 0) {
    Register-Users -AdminToken $adminToken -UserIDsToRegister $missingUserIDs
}
$firstUserToken = Get-UserToken -AdminToken $adminToken -UserID $ResolvedUserIDs[0] -PlatformID $PlatformID

Write-Host "Bootstrap completed."
Write-Host ""
Write-Host "Admin token:"
Write-Host $adminToken
Write-Host ""
Write-Host "Users checked:"
Write-Host ($ResolvedUserIDs -join ", ")
Write-Host ""
Write-Host "Users created in this run:"
if ($missingUserIDs.Count -gt 0) {
    Write-Host ($missingUserIDs -join ", ")
} else {
    Write-Host "(none, all users already existed)"
}
Write-Host ""
Write-Host "First user token ($($ResolvedUserIDs[0])):"
Write-Host $firstUserToken
Write-Host ""
Write-Host "Service endpoints:"
Write-Host "  API: $ResolvedApiBaseUrl"
Write-Host "  WebSocket: ws://127.0.0.1:$defaultMsgGatewayPort"
Write-Host "  MinIO Console: http://127.0.0.1:$defaultMinioConsolePort"
