param(
    [string]$CouncilRoot = "X:\Code\the-ai-counsel",
    [int]$DefaultModelTimeoutSeconds = 300,
    [int]$DefaultSearchTimeoutSeconds = 60
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

function Write-File {
    param(
        [string]$Path,
        [string]$Text
    )
    Set-Content -Path $Path -Value $Text -Encoding UTF8
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

$CouncilRoot = (Resolve-Path $CouncilRoot).Path
$SettingsJsx = Join-Path $CouncilRoot "frontend\src\components\Settings.jsx"
$CouncilConfigJsx = Join-Path $CouncilRoot "frontend\src\components\settings\CouncilConfig.jsx"
$SettingsJson = Join-Path $CouncilRoot "data\settings.json"

Backup-File $SettingsJsx
Backup-File $CouncilConfigJsx

# -----------------------------------------------------------------------------
# Patch Settings.jsx state/load/change/save/props wiring.
# -----------------------------------------------------------------------------
$text = Get-Content $SettingsJsx -Raw
$original = $text

if ($text -notmatch "modelTimeoutSeconds") {
    $text = $text.Replace(
@'
  const [councilTemperature, setCouncilTemperature] = useState(0.5);
  const [chairmanTemperature, setChairmanTemperature] = useState(0.4);
  const [stage2Temperature, setStage2Temperature] = useState(0.3);
'@,
@'
  const [councilTemperature, setCouncilTemperature] = useState(0.5);
  const [chairmanTemperature, setChairmanTemperature] = useState(0.4);
  const [stage2Temperature, setStage2Temperature] = useState(0.3);
  const [modelTimeoutSeconds, setModelTimeoutSeconds] = useState(300);
  const [searchTimeoutSeconds, setSearchTimeoutSeconds] = useState(60);
'@
    )
}

if ($text -notmatch "settings\.model_timeout_seconds") {
    $text = $text.Replace(
@'
      if (councilTemperature !== (settings.council_temperature ?? 0.5)) return true;
      if (chairmanTemperature !== (settings.chairman_temperature ?? 0.4)) return true;
      if (stage2Temperature !== (settings.stage2_temperature ?? 0.3)) return true;
'@,
@'
      if (councilTemperature !== (settings.council_temperature ?? 0.5)) return true;
      if (chairmanTemperature !== (settings.chairman_temperature ?? 0.4)) return true;
      if (stage2Temperature !== (settings.stage2_temperature ?? 0.3)) return true;
      if (modelTimeoutSeconds !== (settings.model_timeout_seconds ?? 300)) return true;
      if (searchTimeoutSeconds !== (settings.search_timeout_seconds ?? 60)) return true;
'@
    )
}

if ($text -notmatch "setModelTimeoutSeconds") {
    $text = $text.Replace(
@'
      setCouncilTemperature(data.council_temperature ?? 0.5);
      setChairmanTemperature(data.chairman_temperature ?? 0.4);
      setStage2Temperature(data.stage2_temperature ?? 0.3);
'@,
@'
      setCouncilTemperature(data.council_temperature ?? 0.5);
      setChairmanTemperature(data.chairman_temperature ?? 0.4);
      setStage2Temperature(data.stage2_temperature ?? 0.3);
      setModelTimeoutSeconds(data.model_timeout_seconds ?? 300);
      setSearchTimeoutSeconds(data.search_timeout_seconds ?? 60);
'@
    )
}

# Add timeout states to the useEffect dependency list if the temperature dependencies exist.
if ($text -notmatch "modelTimeoutSeconds,\s*\r?\n\s*searchTimeoutSeconds") {
    $text = $text.Replace(
@'
    councilTemperature,
    chairmanTemperature,
    stage2Temperature,
'@,
@'
    councilTemperature,
    chairmanTemperature,
    stage2Temperature,
    modelTimeoutSeconds,
    searchTimeoutSeconds,
'@
    )
}

# Add timeout settings to the save payload. This targets the normal settings save object.
if ($text -notmatch "model_timeout_seconds:\s*modelTimeoutSeconds") {
    $text = $text.Replace(
@'
        council_temperature: councilTemperature,
        chairman_temperature: chairmanTemperature,
        stage2_temperature: stage2Temperature,
'@,
@'
        council_temperature: councilTemperature,
        chairman_temperature: chairmanTemperature,
        stage2_temperature: stage2Temperature,
        model_timeout_seconds: modelTimeoutSeconds,
        search_timeout_seconds: searchTimeoutSeconds,
'@
    )
}

# Pass props down to CouncilConfig.
if ($text -notmatch "modelTimeoutSeconds=\{modelTimeoutSeconds\}") {
    $text = $text.Replace(
@'
          chairmanTemperature={chairmanTemperature}
          setChairmanTemperature={setChairmanTemperature}
'@,
@'
          chairmanTemperature={chairmanTemperature}
          setChairmanTemperature={setChairmanTemperature}
          modelTimeoutSeconds={modelTimeoutSeconds}
          setModelTimeoutSeconds={setModelTimeoutSeconds}
          searchTimeoutSeconds={searchTimeoutSeconds}
          setSearchTimeoutSeconds={setSearchTimeoutSeconds}
'@
    )
}

if ($text -ne $original) {
    Write-File -Path $SettingsJsx -Text $text
    Write-Host "Patched Settings.jsx timeout state/save wiring"
} else {
    Write-Host "Settings.jsx already appeared patched or patterns were not found"
}

# -----------------------------------------------------------------------------
# Patch CouncilConfig.jsx prop destructuring and render a timeout card.
# -----------------------------------------------------------------------------
$text = Get-Content $CouncilConfigJsx -Raw
$original = $text

if ($text -notmatch "modelTimeoutSeconds") {
    $text = $text.Replace(
@'
    chairmanTemperature,
    setChairmanTemperature,
    // Data
'@,
@'
    chairmanTemperature,
    setChairmanTemperature,
    modelTimeoutSeconds,
    setModelTimeoutSeconds,
    searchTimeoutSeconds,
    setSearchTimeoutSeconds,
    // Data
'@
    )
}

$timeoutCard = @'

                    {/* Timeout Settings */}
                    <div className="subsection" style={{ marginTop: '20px' }}>
                        <div className="heat-slider-header">
                            <h4>Timeouts</h4>
                        </div>
                        <p className="section-description" style={{ marginTop: 0 }}>
                            Maximum wait time before a model or search request is treated as failed. Increase this for slower Notion-backed models.
                        </p>
                        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '12px', alignItems: 'end' }}>
                            <label style={{ display: 'flex', flexDirection: 'column', gap: '6px' }}>
                                <span>Model timeout seconds</span>
                                <input
                                    type="number"
                                    min="30"
                                    max="1800"
                                    step="30"
                                    value={modelTimeoutSeconds ?? 300}
                                    onChange={(e) => setModelTimeoutSeconds(Math.max(30, Math.min(1800, parseInt(e.target.value || '300', 10))))}
                                    className="settings-input"
                                />
                            </label>
                            <label style={{ display: 'flex', flexDirection: 'column', gap: '6px' }}>
                                <span>Search timeout seconds</span>
                                <input
                                    type="number"
                                    min="10"
                                    max="600"
                                    step="10"
                                    value={searchTimeoutSeconds ?? 60}
                                    onChange={(e) => setSearchTimeoutSeconds(Math.max(10, Math.min(600, parseInt(e.target.value || '60', 10))))}
                                    className="settings-input"
                                />
                            </label>
                        </div>
                        <div className="heat-warning" style={{ marginTop: '10px' }}>
                            Model timeout applies to Stage 1, Stage 2, and Chairman calls. Search timeout is persisted for config parity; search internals may require the backend timeout patch to fully enforce it.
                        </div>
                    </div>
'@

if ($text -notmatch "Model timeout seconds") {
    # Insert the card after the Chairman Heat subsection, immediately before the enclosing Chairman section closes.
    $needle = @'
                    </div>
                </div>

            </section>
'@
    $replacement = @"
                    </div>$timeoutCard
                </div>

            </section>
"@
    if ($text.Contains($needle)) {
        $text = $text.Replace($needle, $replacement)
    } else {
        # Fallback: place before the final settings section close.
        $text = [regex]::Replace($text, "(?s)(\s*</section>\s*</>\s*\);\s*}\s*)$", "$timeoutCard`$1", 1)
    }
}

if ($text -ne $original) {
    Write-File -Path $CouncilConfigJsx -Text $text
    Write-Host "Patched CouncilConfig.jsx timeout UI"
} else {
    Write-Host "CouncilConfig.jsx already appeared patched or patterns were not found"
}

# Persist default values immediately so the UI has sane values on next load.
Set-JsonProperty -Path $SettingsJson -Name "model_timeout_seconds" -Value $DefaultModelTimeoutSeconds
Set-JsonProperty -Path $SettingsJson -Name "search_timeout_seconds" -Value $DefaultSearchTimeoutSeconds
Write-Host "Set defaults in $SettingsJson"

Write-Host ""
Write-Host "Next steps:"
Write-Host "  1. Make sure the backend timeout patch has been applied:"
Write-Host "     powershell -ExecutionPolicy Bypass -File .\scripts\patch-llm-council-timeouts.ps1 -CouncilRoot $CouncilRoot -ModelTimeoutSeconds $DefaultModelTimeoutSeconds"
Write-Host "  2. Restart the stack:"
Write-Host "     .\stop.bat"
Write-Host "     .\launch.bat"
Write-Host "  3. Open Settings > Council and adjust the Timeouts section."
Pause
