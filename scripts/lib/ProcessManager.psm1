function Test-PortInUse {
    param([int]$Port)
    $listeners = [System.Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties().GetActiveTcpListeners()
    return [bool]($listeners | Where-Object { $_.Port -eq $Port })
}

function Get-ListeningProcessId {
    param([int]$Port)
    try {
        $connection = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction Stop |
            Select-Object -First 1
        if ($connection) {
            return [int]$connection.OwningProcess
        }
    } catch {
        return 0
    }
    return 0
}

function Find-FreePort {
    param(
        [int]$PreferredPort,
        [int[]]$Alternates = @()
    )

    foreach ($candidate in @($PreferredPort) + $Alternates) {
        if (-not (Test-PortInUse -Port $candidate)) {
            return $candidate
        }
    }

    for ($candidate = $PreferredPort + 1; $candidate -lt $PreferredPort + 100; $candidate++) {
        if (-not (Test-PortInUse -Port $candidate)) {
            return $candidate
        }
    }

    throw "No free local port found near $PreferredPort."
}

function Stop-ProcessId {
    param(
        [int]$ProcessId,
        [switch]$Tree
    )
    if ($ProcessId -le 0 -or $ProcessId -eq $PID) {
        return
    }

    $process = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
    if ($process) {
        if ($Tree) {
            Write-Host "Stopping process tree for PID $ProcessId ($($process.Name))"
            # Attempt to kill the process and its children
            taskkill /F /T /PID $ProcessId 2>$null
        } else {
            Write-Host "Stopping PID $ProcessId ($($process.Name))"
            Stop-Process -Id $ProcessId -Force -ErrorAction SilentlyContinue
        }
    }
}

Export-ModuleMember -Function Test-PortInUse, Get-ListeningProcessId, Find-FreePort, Stop-ProcessId
