<#
  .SYNOPSIS Creates the RSA key pair that the pipeline user (ELIO_SVC) uses to sign in to Snowflake. .DESCRIPTION
  Writes two files OUTSIDE the repo: rsa_key.p8 PRIVATE key.
#>
param(
    [string]$OutDir = (Join-Path $HOME '.snowflake\elio'),
    [switch]$Force      # overwrite an existing key (this invalidates the old one)
)

$ErrorActionPreference = 'Stop'
$private = Join-Path $OutDir 'rsa_key.p8'
$public  = Join-Path $OutDir 'rsa_key.pub'

# --- 1. Guard: never silently replace a key that Snowflake may already trust ---
if ((Test-Path $private) -and -not $Force) {
    throw "A key already exists at $private. Re-run with -Force only if you want to replace it."
}

# --- 2. Find openssl ---------------------------------------------------------- Git for Windows ships openssl but
# only puts it on PATH inside Git Bash, so a plain PowerShell window often can't see it.
$openssl = $null
$onPath = Get-Command openssl -ErrorAction SilentlyContinue
if ($onPath) { $openssl = $onPath.Source }
if (-not $openssl) {
    $candidates = @(
        "$env:ProgramFiles\Git\mingw64\bin\openssl.exe",
        "$env:ProgramFiles\Git\usr\bin\openssl.exe",
        "$env:LOCALAPPDATA\Programs\Git\mingw64\bin\openssl.exe"
    )
    $git = Get-Command git -ErrorAction SilentlyContinue
    if ($git) {   # ...\Git\cmd\git.exe  ->  ...\Git\mingw64\bin\openssl.exe
        $candidates += Join-Path (Split-Path (Split-Path $git.Source)) 'mingw64\bin\openssl.exe'
    }
    $openssl = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
}
if (-not $openssl) {
    throw "openssl not found. Install Git for Windows (it includes openssl) or add openssl to PATH."
}
Write-Host "Using openssl: $openssl"

# --- 3. Make the folder -------------------------------------------------------
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

# --- 4. Generate the private key (2048-bit RSA, PKCS#8, unencrypted) ---------- genpkey writes PKCS#8 directly, which
# is the format Snowflake's drivers expect.
$ErrorActionPreference = 'Continue'
$out = & $openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out $private 2>&1
if ($LASTEXITCODE -ne 0) { throw "openssl failed creating the private key:`n$out" }

# --- 5. Derive the public key from the private key ---------------------------
$out = & $openssl pkey -in $private -pubout -out $public 2>&1
if ($LASTEXITCODE -ne 0) { throw "openssl failed creating the public key:`n$out" }
$ErrorActionPreference = 'Stop'

# --- 6. Lock the private key file to your Windows user only ------------------ Removes inherited permissions, then
# grants read/write to you alone.
$mySid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
& icacls $private /inheritance:r /grant:r "*${mySid}:(R,W)" | Out-Null
if ($LASTEXITCODE -ne 0) { throw "icacls failed to restrict the private key" }
# Prove we can still read our own key (fail loudly rather than hand over a locked file).
$null = Get-Content $private -TotalCount 1

# --- 7. One-line public key: drop the BEGIN/END lines, join the rest ---------
$onePublic = (Get-Content $public | Where-Object { $_ -notmatch '^-----' }) -join ''

# --- 8. Fingerprint, computed the way Snowflake does -------------------------
#    SHA-256 of the DER-encoded public key (= the base64 body decoded), then base64.
$der = [Convert]::FromBase64String($onePublic)
$sha = [Security.Cryptography.SHA256]::Create()
$fingerprint = 'SHA256:' + [Convert]::ToBase64String($sha.ComputeHash($der))

# --- 9. Report (the private key is never printed) ----------------------------
Write-Host ""
Write-Host "Private key (keep secret): $private"
Write-Host "Public key file:           $public"
Write-Host ""
Write-Host "Public key, one line, paste into 00_setup_account.sql:"
Write-Host $onePublic -ForegroundColor Cyan
Write-Host ""
Write-Host "Fingerprint to compare with Snowflake's RSA_PUBLIC_KEY_FP:"
Write-Host $fingerprint -ForegroundColor Cyan
