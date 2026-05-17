function Test-HttpOk
{
    param(
        [string]$Url,
        [string]$ExpectedTitle = "",
        [string]$ExpectedContent = "",
        [string]$BearerToken = ""
    )
    try {
        $headers = @{}
        if ($BearerToken) {
            $headers["Authorization"] = "Bearer $BearerToken"
        }
        $response = Invoke-WebRequest -UseBasicParsing -Uri $Url -TimeoutSec 2 -Headers $headers
        if ($response.StatusCode -lt 200 -or $response.StatusCode -ge 500) {
            return $false
        }
        if ($ExpectedTitle) {
            $titleMatch = [regex]::Match($response.Content, '<title>(.*?)</title>', 'Singleline,IgnoreCase')
            if (-not ($titleMatch.Success -and $titleMatch.Groups[1].Value.Contains($ExpectedTitle))) {
                return $false
            }
        }
        if ($ExpectedContent -and -not ($response.Content.Contains($ExpectedContent))) {
            return $false
        }
        return $true
    } catch {
        return $false
    }
}

function Wait-HttpOk
{
    param(
        [string]$Url,
        [int]$TimeoutSeconds = 45,
        [string]$ExpectedTitle = "",
        [string]$ExpectedContent = ""
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        if (Test-HttpOk -Url $Url -ExpectedTitle $ExpectedTitle -ExpectedContent $ExpectedContent) {
            return
        }
        Start-Sleep -Milliseconds 750
    } while ((Get-Date) -lt $deadline)

    throw "Timed out waiting for $Url"
}

Export-ModuleMember -Function Test-HttpOk, Wait-HttpOk
