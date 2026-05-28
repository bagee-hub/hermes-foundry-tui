$ErrorActionPreference = "Stop"

$RepoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$OutDir = Join-Path $RepoRoot "agent/hermes-defaults"
$OutFile = Join-Path $OutDir "config.yaml"

function Get-AzdEnvValue {
    param([Parameter(Mandatory = $true)][string]$Name)

    $value = azd env get-value $Name 2>$null
    if ($LASTEXITCODE -ne 0 -or $null -eq $value) {
        return ""
    }
    return (($value -join "`n").Trim())
}

function Get-RequiredAzdEnvValue {
    param([Parameter(Mandatory = $true)][string]$Name)

    $value = Get-AzdEnvValue $Name
    if ([string]::IsNullOrWhiteSpace($value)) {
        throw "$Name is not set in the azd environment. Run azd provision before packaging or deploying."
    }
    return $value
}

function Normalize-FoundryBaseUrl {
    param([Parameter(Mandatory = $true)][string]$Value)

    $baseUrl = $Value.Trim().TrimEnd("/")
    $lower = $baseUrl.ToLowerInvariant()
    if ($lower.EndsWith("/openai/v1")) {
        return $baseUrl
    }
    if ($lower.EndsWith("/openai")) {
        return "$baseUrl/v1"
    }
    if ($lower.Contains(".openai.azure.com")) {
        return "$baseUrl/openai/v1"
    }
    return $baseUrl
}

function ConvertTo-YamlDoubleQuotedString {
    param([Parameter(Mandatory = $true)][string]$Value)

    return $Value.Replace('\', '\\').Replace('"', '\"')
}

function Format-YamlScalarLine {
    param(
        [Parameter(Mandatory = $true)][string]$Key,
        [Parameter(Mandatory = $true)][string]$Value
    )

    return '  ' + $Key + ': "' + (ConvertTo-YamlDoubleQuotedString $Value) + '"'
}

$DeploymentName = Get-RequiredAzdEnvValue "AZURE_FOUNDRY_MODEL_DEPLOYMENT_NAME"
$BaseUrl = Normalize-FoundryBaseUrl (Get-RequiredAzdEnvValue "AZURE_FOUNDRY_BASE_URL")
$ApiMode = Get-RequiredAzdEnvValue "AZURE_FOUNDRY_MODEL_API_MODE"
$AuthMode = Get-AzdEnvValue "AZURE_FOUNDRY_AUTH_MODE"
if ([string]::IsNullOrWhiteSpace($AuthMode)) {
    $AuthMode = "entra_id"
}
switch ($AuthMode) {
    "entra_id" {}
    "api_key" {}
    default {
        throw "Unsupported AZURE_FOUNDRY_AUTH_MODE '$AuthMode'. Expected 'entra_id' or 'api_key'."
    }
}

if ([string]::IsNullOrWhiteSpace($BaseUrl)) {
    throw "AZURE_FOUNDRY_BASE_URL resolved to an empty base URL."
}

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
Remove-Item -Force -ErrorAction SilentlyContinue $OutFile

$Lines = @(
    "model:",
    (Format-YamlScalarLine "provider" "azure-foundry"),
    (Format-YamlScalarLine "default" $DeploymentName),
    (Format-YamlScalarLine "base_url" $BaseUrl),
    (Format-YamlScalarLine "api_mode" $ApiMode),
    (Format-YamlScalarLine "auth_mode" $AuthMode)
)
$Lines | Set-Content -Path $OutFile -Encoding utf8

Write-Host "Rendered Hermes config: agent/hermes-defaults/config.yaml"
