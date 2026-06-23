# Lumen - Lua syntax/lint check ueber alle Addon-Dateien.
# Libs/ und tools/ werden via .luacheckrc uebersprungen.
# Aufruf:  powershell tools\check.ps1
$exe = Join-Path $PSScriptRoot 'luacheck.exe'
if (-not (Test-Path $exe)) {
    Write-Host 'luacheck.exe fehlt unter tools\ - siehe CLAUDE.md (Download-Link).' -ForegroundColor Red
    exit 1
}
$repo = Split-Path $PSScriptRoot -Parent
Push-Location $repo
try { & $exe . } finally { Pop-Location }
exit $LASTEXITCODE
