param(
    [string]$Profile = "default"
)

$ErrorActionPreference = "Stop"

# Ensure the DPAPI types are available (Windows PowerShell 5.1)
try {
    Add-Type -AssemblyName System.Security -ErrorAction Stop
} catch {
    Write-Verbose "System.Security already loaded or not required."
}

$token = $env:GITHUB_TOKEN
if (-not $token) {
    $sec = Read-Host -AsSecureString "Enter a fine-grained GitHub PAT (scoped to your repo only)"
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
    try { $token = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) } finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
}

if (-not $token) { Write-Error "No token provided."; exit 2 }

$dir = Join-Path $env:APPDATA "AutoBackupAgent"
New-Item -ItemType Directory -Force -Path $dir | Out-Null

# DPAPI protect for current user
$bytes = [System.Text.Encoding]::UTF8.GetBytes($token)
$prot  = [System.Security.Cryptography.ProtectedData]::Protect($bytes, $null, [System.Security.Cryptography.DataProtectionScope]::CurrentUser)

[IO.File]::WriteAllBytes((Join-Path $dir 'token.bin'), $prot)
Write-Host "Token stored securely for current user at $dir\token.bin" -ForegroundColor Green
