function ConvertTo-CouncilProviderUrl
{
    param($Url)

    if ($null -eq $Url) { return "" }

    $value = ([string]$Url).Trim()
    if (-not $value) { return "" }

    try {
        $builder = [System.UriBuilder]::new($value)
        $builder.Scheme = $builder.Scheme.ToLowerInvariant()
        if ($builder.Host -in @("localhost", "127.0.0.1")) {
            $builder.Host = "127.0.0.1"
        } else {
            $builder.Host = $builder.Host.ToLowerInvariant()
        }
        $builder.Path = $builder.Path.TrimEnd("/")
        return $builder.Uri.AbsoluteUri.TrimEnd("/")
    } catch {
        return $value.TrimEnd("/")
    }
}

function ConvertTo-CouncilSecretValue
{
    param($Value)

    if ($null -eq $Value) { return "" }
    return ([string]$Value).Trim()
}

function Get-CouncilSecretDiagnostic
{
    param($Value)

    $normalized = ConvertTo-CouncilSecretValue -Value $Value
    if (-not $normalized) { return "empty" }
    return "length $($normalized.Length)"
}

function Test-CouncilProviderSettings
{
    param(
        $Settings,
        [string]$ExpectedUrl,
        [string]$ExpectedApiKey
    )

    $issues = @()
    if ($null -eq $Settings) {
        $issues += "settings payload is missing"
        return [PSCustomObject]@{ Ok = $false; Issues = $issues }
    }

    $actualUrl = ConvertTo-CouncilProviderUrl -Url $Settings.custom_endpoint_url
    $canonicalExpectedUrl = ConvertTo-CouncilProviderUrl -Url $ExpectedUrl
    if ($actualUrl -cne $canonicalExpectedUrl) {
        $issues += "custom_endpoint_url is '$actualUrl', expected '$canonicalExpectedUrl'"
    }

    $actualKey = ConvertTo-CouncilSecretValue -Value $Settings.custom_endpoint_api_key
    $expectedKey = ConvertTo-CouncilSecretValue -Value $ExpectedApiKey
    if ($actualKey -cne $expectedKey) {
        $issues += "custom_endpoint_api_key mismatch (actual $(Get-CouncilSecretDiagnostic -Value $actualKey), expected $(Get-CouncilSecretDiagnostic -Value $expectedKey))"
    }

    if (-not $Settings.enabled_providers -or $Settings.enabled_providers.custom -ne $true) {
        $issues += "custom provider is not enabled"
    }

    return [PSCustomObject]@{ Ok = ($issues.Count -eq 0); Issues = $issues }
}

function Test-CouncilProviderSettingsOrThrow
{
    param(
        $Settings,
        [string]$ExpectedUrl,
        [string]$ExpectedApiKey
    )

    $result = Test-CouncilProviderSettings -Settings $Settings -ExpectedUrl $ExpectedUrl -ExpectedApiKey $ExpectedApiKey
    if (-not $result.Ok) {
        throw "LLM Council provider verification failed: $($result.Issues -join '; ')"
    }
}

Export-ModuleMember -Function ConvertTo-CouncilProviderUrl, ConvertTo-CouncilSecretValue, Get-CouncilSecretDiagnostic, Test-CouncilProviderSettings, Test-CouncilProviderSettingsOrThrow
