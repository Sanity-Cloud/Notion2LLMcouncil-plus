param(
    [string]$CouncilRoot = "X:\Code\the-ai-counsel",
    [int]$ModelTimeoutSeconds = 300,
    [switch]$RestartBackend
)

$ErrorActionPreference = "Stop"

function Backup-File {
    param([string]$Path)
    if (-not (Test-Path $Path)) {
        throw "File not found: $Path"
    }
    $backup = "$Path.bak_$(Get-Date -Format yyyyMMdd_HHmmss)"
    Copy-Item $Path $backup -Force
    Write-Host "Backup: $backup"
}

function Replace-Required {
    param(
        [string]$Path,
        [string]$Old,
        [string]$New,
        [string]$Label
    )
    $text = Get-Content $Path -Raw
    if ($text.Contains($New)) {
        Write-Host "Already patched: $Label"
        return
    }
    if (-not $text.Contains($Old)) {
        Write-Warning "Pattern not found for: $Label"
        return
    }
    $text = $text.Replace($Old, $New)
    Set-Content -Path $Path -Value $text -Encoding UTF8
    Write-Host "Patched: $Label"
}

function Set-JsonProperty {
    param(
        [string]$Path,
        [string]$Name,
        $Value
    )
    $settings = if (Test-Path $Path) {
        try { Get-Content -Path $Path -Raw | ConvertFrom-Json } catch { [pscustomobject]@{} }
    } else {
        [pscustomobject]@{}
    }
    $settings | Add-Member -MemberType NoteProperty -Name $Name -Value $Value -Force
    $dir = Split-Path $Path -Parent
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $settings | ConvertTo-Json -Depth 30 | Set-Content -Path $Path -Encoding UTF8
}

function Restart-CouncilBackend {
    param([string]$Root)
    $resolved = (Resolve-Path $Root).Path
    $escaped = [regex]::Escape($resolved)
    $targets = Get-CimInstance Win32_Process | Where-Object {
        $_.CommandLine -and $_.CommandLine -match $escaped -and $_.CommandLine -match "backend\.main|uvicorn.*backend\.main"
    }
    foreach ($target in $targets) {
        Write-Host "Stopping backend PID $($target.ProcessId)"
        Stop-Process -Id $target.ProcessId -Force -ErrorAction SilentlyContinue
    }
}

$CouncilRoot = (Resolve-Path $CouncilRoot).Path
$SettingsPy = Join-Path $CouncilRoot "backend\settings.py"
$MainPy = Join-Path $CouncilRoot "backend\main.py"
$CouncilPy = Join-Path $CouncilRoot "backend\council.py"
$SettingsJson = Join-Path $CouncilRoot "data\settings.json"

Backup-File $SettingsPy
Backup-File $MainPy
Backup-File $CouncilPy

# 1. Add persistent timeout fields to backend/settings.py.
Replace-Required `
    -Path $SettingsPy `
    -Old @'
    # Temperature Settings
    council_temperature: float = 0.5
    chairman_temperature: float = 0.4
    stage2_temperature: float = 0.3  # Lower for consistent ranking output
'@ `
    -New @'
    # Temperature Settings
    council_temperature: float = 0.5
    chairman_temperature: float = 0.4
    stage2_temperature: float = 0.3  # Lower for consistent ranking output

    # Timeout Settings
    model_timeout_seconds: int = 300  # Max seconds per model request
    search_timeout_seconds: int = 60  # Reserved for search timeout UI/config parity
'@ `
    -Label "settings.py timeout fields"

# 2. Add timeout fields to update request in backend/main.py.
Replace-Required `
    -Path $MainPy `
    -Old @'
    # Temperature Settings
    council_temperature: Optional[float] = None
    chairman_temperature: Optional[float] = None
    stage2_temperature: Optional[float] = None

    # Execution Mode
'@ `
    -New @'
    # Temperature Settings
    council_temperature: Optional[float] = None
    chairman_temperature: Optional[float] = None
    stage2_temperature: Optional[float] = None

    # Timeout Settings
    model_timeout_seconds: Optional[int] = None
    search_timeout_seconds: Optional[int] = None

    # Execution Mode
'@ `
    -Label "main.py UpdateSettingsRequest timeout fields"

# 3. Return timeout fields from GET /api/settings.
Replace-Required `
    -Path $MainPy `
    -Old @'
        # Temperature Settings
        "council_temperature": settings.council_temperature,
        "chairman_temperature": settings.chairman_temperature,
        "stage2_temperature": settings.stage2_temperature,

        # Prompts
'@ `
    -New @'
        # Temperature Settings
        "council_temperature": settings.council_temperature,
        "chairman_temperature": settings.chairman_temperature,
        "stage2_temperature": settings.stage2_temperature,

        # Timeout Settings
        "model_timeout_seconds": settings.model_timeout_seconds,
        "search_timeout_seconds": settings.search_timeout_seconds,

        # Prompts
'@ `
    -Label "main.py GET /api/settings timeout fields"

# 4. Persist timeout fields in PUT /api/settings.
Replace-Required `
    -Path $MainPy `
    -Old @'
    # Temperature Settings
    if request.council_temperature is not None:
        updates["council_temperature"] = request.council_temperature
    if request.chairman_temperature is not None:
        updates["chairman_temperature"] = request.chairman_temperature
    if request.stage2_temperature is not None:
        updates["stage2_temperature"] = request.stage2_temperature

    # Prompts   # Execution Mode
'@ `
    -New @'
    # Temperature Settings
    if request.council_temperature is not None:
        updates["council_temperature"] = request.council_temperature
    if request.chairman_temperature is not None:
        updates["chairman_temperature"] = request.chairman_temperature
    if request.stage2_temperature is not None:
        updates["stage2_temperature"] = request.stage2_temperature

    # Timeout Settings
    if request.model_timeout_seconds is not None:
        if request.model_timeout_seconds < 30 or request.model_timeout_seconds > 1800:
            raise HTTPException(status_code=400, detail="model_timeout_seconds must be between 30 and 1800")
        updates["model_timeout_seconds"] = request.model_timeout_seconds
    if request.search_timeout_seconds is not None:
        if request.search_timeout_seconds < 10 or request.search_timeout_seconds > 600:
            raise HTTPException(status_code=400, detail="search_timeout_seconds must be between 10 and 600")
        updates["search_timeout_seconds"] = request.search_timeout_seconds

    # Prompts   # Execution Mode
'@ `
    -Label "main.py PUT /api/settings timeout persistence"

# 5. Return timeout fields from PUT /api/settings response.
Replace-Required `
    -Path $MainPy `
    -Old @'
        # Prompts
        "stage1_prompt": settings.stage1_prompt,
'@ `
    -New @'
        # Timeout Settings
        "model_timeout_seconds": settings.model_timeout_seconds,
        "search_timeout_seconds": settings.search_timeout_seconds,

        # Prompts
        "stage1_prompt": settings.stage1_prompt,
'@ `
    -Label "main.py PUT response timeout fields"

# 6. Pass configured timeout into Stage 1, Stage 2, and Chairman model calls.
Replace-Required `
    -Path $CouncilPy `
    -Old @'
    council_temp = settings.council_temperature

    async def _query_safe(m: str):
        try:
            return m, await query_model(m, messages, temperature=council_temp)
'@ `
    -New @'
    council_temp = settings.council_temperature
    model_timeout = getattr(settings, "model_timeout_seconds", 300)

    async def _query_safe(m: str):
        try:
            return m, await query_model(m, messages, timeout=model_timeout, temperature=council_temp)
'@ `
    -Label "council.py Stage 1 model timeout"

Replace-Required `
    -Path $CouncilPy `
    -Old @'
    stage2_temp = settings.stage2_temperature

    async def _query_safe(m: str):
        try:
            return m, await query_model(m, messages, temperature=stage2_temp)
'@ `
    -New @'
    stage2_temp = settings.stage2_temperature
    model_timeout = getattr(settings, "model_timeout_seconds", 300)

    async def _query_safe(m: str):
        try:
            return m, await query_model(m, messages, timeout=model_timeout, temperature=stage2_temp)
'@ `
    -Label "council.py Stage 2 model timeout"

Replace-Required `
    -Path $CouncilPy `
    -Old @'
    chairman_temp = settings.chairman_temperature

    try:
        response = await query_model(chairman_model, messages, temperature=chairman_temp)
'@ `
    -New @'
    chairman_temp = settings.chairman_temperature
    model_timeout = getattr(settings, "model_timeout_seconds", 300)

    try:
        response = await query_model(chairman_model, messages, timeout=model_timeout, temperature=chairman_temp)
'@ `
    -Label "council.py Chairman model timeout"

# 7. Persist selected default in data/settings.json.
Set-JsonProperty -Path $SettingsJson -Name "model_timeout_seconds" -Value $ModelTimeoutSeconds
Set-JsonProperty -Path $SettingsJson -Name "search_timeout_seconds" -Value 60
Write-Host "Set model_timeout_seconds=$ModelTimeoutSeconds in $SettingsJson"

Write-Host ""
Write-Host "Verify after backend restart:"
Write-Host "  Invoke-RestMethod http://127.0.0.1:8001/api/settings | Select-Object model_timeout_seconds, search_timeout_seconds | Format-List"

if ($RestartBackend) {
    Restart-CouncilBackend -Root $CouncilRoot
    Write-Host "Backend stopped. Restart with your normal launcher."
}

Pause
