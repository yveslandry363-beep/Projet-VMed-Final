param(
    [string]$RepoUrl,
    [string]$Branch = "main",
    [string]$Path = "."
)

Write-Host "=== AutoBackupAgent Secure Runner ===" -ForegroundColor Cyan

# Resolve path
$Path = (Resolve-Path $Path).Path

# Ask for repo URL if not provided
if (-not $RepoUrl) {
    $RepoUrl = Read-Host "Enter GitHub repo URL (https://github.com/<org>/<repo>.git)"
}

if (-not $RepoUrl) {
    Write-Error "REPO_URL is required."; exit 2
}

# Token: prefer env var, otherwise prompt securely
$token = $env:GITHUB_TOKEN
if (-not $token) {
    $sec = Read-Host -AsSecureString "Enter a fine-grained GitHub PAT (scoped to this repo only)"
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
    try { $token = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) } finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
}

if (-not $token) {
    Write-Error "GITHUB_TOKEN is required to push securely."; exit 3
}

# Run agent with temporary env vars
$prevRepo = $env:REPO_URL
$prevToken = $env:GITHUB_TOKEN
$prevBranch = $env:BRANCH
$prevWatch = $env:WATCH_PATH

try {
    $env:REPO_URL = $RepoUrl
    $env:GITHUB_TOKEN = $token
    $env:BRANCH = $Branch
    $env:WATCH_PATH = $Path

    Write-Host "Repo: $RepoUrl" -ForegroundColor Green
    Write-Host "Branch: $Branch" -ForegroundColor Green
    Write-Host "Path: $Path" -ForegroundColor Green
    Write-Host "Starting watcher... (Ctrl+C to stop)" -ForegroundColor Yellow

    dotnet run --project .\Tools\AutoBackupAgent\AutoBackupAgent.csproj -- --path "$Path" --branch "$Branch" --repo "$RepoUrl"
}
finally {
    # Clean up env
    if ($null -eq $prevRepo) { Remove-Item Env:REPO_URL -ErrorAction SilentlyContinue } else { $env:REPO_URL = $prevRepo }
    if ($null -eq $prevToken) { Remove-Item Env:GITHUB_TOKEN -ErrorAction SilentlyContinue } else { $env:GITHUB_TOKEN = $prevToken }
    if ($null -eq $prevBranch) { Remove-Item Env:BRANCH -ErrorAction SilentlyContinue } else { $env:BRANCH = $prevBranch }
    if ($null -eq $prevWatch) { Remove-Item Env:WATCH_PATH -ErrorAction SilentlyContinue } else { $env:WATCH_PATH = $prevWatch }
}
