param(
    [string]$RepoUrl,
    [string]$Branch = "main",
    [string]$Path = ".",
    [switch]$RunNow
)

$ErrorActionPreference = "Stop"

if (-not $RepoUrl) { $RepoUrl = Read-Host "Enter GitHub repo URL (https://github.com/<org>/<repo>.git)" }
if (-not $RepoUrl) { throw "REPO_URL is required." }

$fullPath = (Resolve-Path $Path).Path

# Ensure token is saved securely
$tokenFile = Join-Path $env:APPDATA "AutoBackupAgent\token.bin"
if (-not (Test-Path $tokenFile)) {
    Write-Host "No token found. We'll save one now (DPAPI-protected for current user)." -ForegroundColor Yellow
    .\save-github-token.ps1
}

$taskName = "AutoBackupAgent"
# Pass the repo URL explicitly so the agent can configure 'origin'
$action = New-ScheduledTaskAction -Execute "dotnet" -Argument "run --project `"$fullPath\Tools\AutoBackupAgent\AutoBackupAgent.csproj`" -- --path `"$fullPath`" --branch `"$Branch`" --repo `"$RepoUrl`"" -WorkingDirectory $fullPath
$trigger = New-ScheduledTaskTrigger -AtLogOn

# Choose RunLevel based on elevation to avoid Access Denied when not admin
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$runLevel = if ($isAdmin) { 'Highest' } else { 'Limited' }
$principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel $runLevel
$settings = New-ScheduledTaskSettingsSet -Hidden -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)

try {
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
} catch {}

try {
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -ErrorAction Stop | Out-Null
    Write-Host "Scheduled Task '$taskName' installed. It will start on user logon." -ForegroundColor Green
}
catch {
    if ($_.Exception.Message -match '0x80070005') {
        Write-Warning "Access denied while registering the task. Falling back to Startup folder shortcut (no admin required)."

        # Create Startup shortcut as fallback
        $shell = New-Object -ComObject WScript.Shell
        $startup = [Environment]::GetFolderPath('Startup')
        $lnk = Join-Path $startup 'AutoBackupAgent.lnk'
        $targetPath = 'dotnet'
        $arguments = "run --project `"$fullPath\Tools\AutoBackupAgent\AutoBackupAgent.csproj`" -- --path `"$fullPath`" --branch `"$Branch`" --repo `"$RepoUrl`""
        $shortcut = $shell.CreateShortcut($lnk)
        $shortcut.TargetPath = $targetPath
        $shortcut.Arguments = $arguments
        $shortcut.WorkingDirectory = $fullPath
        $shortcut.WindowStyle = 7  # Minimized
        $shortcut.IconLocation = "$PSHOME\\powershell.exe,0"
        $shortcut.Save()

        Write-Host "Startup shortcut created at: $lnk" -ForegroundColor Yellow
        Write-Host "It will launch at next logon. You can also start it now by running the command below:" -ForegroundColor Yellow
        Write-Host "dotnet $arguments" -ForegroundColor DarkGray
    } else {
        throw
    }
}

if ($RunNow) {
    Start-ScheduledTask -TaskName $taskName
    Write-Host "Task started." -ForegroundColor Green
}
