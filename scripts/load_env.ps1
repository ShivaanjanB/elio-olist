# Loads KEY=VALUE lines from the repo's .env into the current PowerShell session.
$envFile = Join-Path $PSScriptRoot '..\.env'
if (-not (Test-Path $envFile)) { throw ".env not found. Copy .env.example to .env and fill it in." }

$count = 0
foreach ($line in Get-Content $envFile) {
    $line = $line.Trim()
    if ($line -eq '' -or $line.StartsWith('#')) { continue }
    $name, $value = $line -split '=', 2
    [Environment]::SetEnvironmentVariable($name.Trim(), $value.Trim(), 'Process')
    $count++
}
Write-Host "Loaded $count variables from .env"
