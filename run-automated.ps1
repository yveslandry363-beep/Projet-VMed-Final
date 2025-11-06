#Requires -Version 5.1
<#
.SYNOPSIS
    Script d'automatisation complète du Prototype Gemini
.DESCRIPTION
    Build, démarre l'application, et insère automatiquement des données CDC
.PARAMETER SkipBuild
    Ignorer la compilation
.PARAMETER InsertCount
    Nombre d'insertions automatiques (défaut: 5)
.PARAMETER InsertInterval
    Intervalle en secondes entre les insertions (défaut: 10)
#>

param(
    [switch]$SkipBuild,
    [int]$InsertCount = 5,
    [int]$InsertInterval = 10
)

$ErrorActionPreference = "Stop"
$AppProcess = $null

function Write-ColorLog {
    param(
        [string]$Message,
        [string]$Color = "Cyan"
    )
    Write-Host $Message -ForegroundColor $Color
}

function Stop-Application {
    Write-ColorLog "Arret de l'application..." "Yellow"
    
    if ($null -ne $script:AppProcess -and -not $script:AppProcess.HasExited) {
        Stop-Process -Id $script:AppProcess.Id -Force -ErrorAction SilentlyContinue
    }
    
    Get-Process | Where-Object { $_.ProcessName -like '*Prototype*' } | ForEach-Object {
        Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
    }
    
    Write-ColorLog "Nettoyage termine" "Green"
    exit 0
}

# Banner
Clear-Host
Write-ColorLog ""
Write-ColorLog "================================================================" "Cyan"
Write-ColorLog "     AUTOMATISATION COMPLETE - PROTOTYPE GEMINI" "Cyan"
Write-ColorLog "================================================================" "Cyan"
Write-ColorLog ""

# ETAPE 1: Verification
Write-ColorLog "[1/5] Verification de l'environnement" "Cyan"

try {
    $dotnetVer = dotnet --version
    Write-ColorLog "  .NET SDK: $dotnetVer" "Green"
} catch {
    Write-ColorLog "  ERREUR: .NET SDK introuvable" "Red"
    exit 1
}

if (-not (Test-Path "appsettings.json")) {
    Write-ColorLog "  ERREUR: appsettings.json introuvable" "Red"
    exit 1
}
Write-ColorLog "  appsettings.json: OK" "Green"

if (-not (Test-Path "gcp-key.json")) {
    Write-ColorLog "  ERREUR: gcp-key.json introuvable" "Red"
    exit 1
}
Write-ColorLog "  gcp-key.json: OK" "Green"
Write-ColorLog ""

# ETAPE 2: Build
if (-not $SkipBuild) {
    Write-ColorLog "[2/5] Compilation du projet" "Cyan"
    
    $buildOutput = dotnet build --configuration Release 2>&1
    
    if ($LASTEXITCODE -ne 0) {
        Write-ColorLog "  ERREUR: Compilation echouee" "Red"
        exit 1
    }
    
    Write-ColorLog "  Compilation reussie" "Green"
} else {
    Write-ColorLog "[2/5] Compilation ignoree" "Yellow"
}
Write-ColorLog ""

# ETAPE 3: Nettoyage
Write-ColorLog "[3/5] Nettoyage des processus" "Cyan"

$existing = Get-Process | Where-Object { $_.ProcessName -like '*Prototype*' }
if ($existing) {
    $existing | ForEach-Object {
        Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
    }
    Start-Sleep -Seconds 2
}

Write-ColorLog "  Nettoyage termine" "Green"
Write-ColorLog ""

# ETAPE 4: Demarrage
Write-ColorLog "[4/5] Demarrage de l'application" "Cyan"

try {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "dotnet"
    $psi.Arguments = "run --configuration Release --no-build"
    $psi.WorkingDirectory = Get-Location
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    
    $script:AppProcess = New-Object System.Diagnostics.Process
    $script:AppProcess.StartInfo = $psi
    $script:AppProcess.Start() | Out-Null
    
    Write-ColorLog "  Application demarree (PID: $($script:AppProcess.Id))" "Green"
    Write-ColorLog "  Attente du demarrage (30 secondes)..." "Yellow"
    
    Start-Sleep -Seconds 30
    
    if ($script:AppProcess.HasExited) {
        Write-ColorLog "  ERREUR: Application arretee prematurement" "Red"
        exit 1
    }
    
    Write-ColorLog "  Application prete" "Green"
} catch {
    Write-ColorLog "  ERREUR: $($_.Exception.Message)" "Red"
    exit 1
}
Write-ColorLog ""

# ETAPE 5: Insertions
Write-ColorLog "[5/5] Insertion de donnees CDC" "Cyan"

try {
    $config = Get-Content "appsettings.json" -Raw | ConvertFrom-Json
    $connStr = $config.PostgreSql.ConnectionString
    
    $npgsql = Get-ChildItem -Path ".\bin\Release\net9.0" -Filter "Npgsql.dll" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $npgsql) {
        $npgsql = Get-ChildItem -Path ".\bin\Debug\net9.0" -Filter "Npgsql.dll" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    }
    
    if (-not $npgsql) {
        Write-ColorLog "  ERREUR: Npgsql.dll introuvable" "Red"
        Stop-Application
    }
    
    Add-Type -Path $npgsql.FullName
    
    $messages = @(
        "Patient avec fievre elevee et toux persistante",
        "Douleurs abdominales aigues",
        "Hypertension arterielle non controlee",
        "Cephalees severes avec photophobie",
        "Dyspnee au repos, saturation O2 faible"
    )
    
    for ($i = 1; $i -le $InsertCount; $i++) {
        try {
            if ($script:AppProcess.HasExited) {
                Write-ColorLog "  ERREUR: Application arretee" "Red"
                break
            }
            
            $msg = $messages | Get-Random
            
            Write-ColorLog "  [$i/$InsertCount] Insertion..." "Cyan"
            
            $conn = New-Object Npgsql.NpgsqlConnection($connStr)
            $conn.Open()
            
            $cmd = $conn.CreateCommand()
            $cmd.CommandText = "INSERT INTO public.diagnostics (diagnostic_text, ia_guidance) VALUES (@text, @guidance) RETURNING id;"
            $null = $cmd.Parameters.AddWithValue("text", $msg)
            $null = $cmd.Parameters.AddWithValue("guidance", "Auto test $i")
            
            $id = $cmd.ExecuteScalar()
            $conn.Close()
            
            Write-ColorLog "    ID=$id | $msg" "Green"
            
            if ($i -lt $InsertCount) {
                Start-Sleep -Seconds $InsertInterval
            }
        } catch {
            Write-ColorLog "    ERREUR: $($_.Exception.Message)" "Red"
        }
    }
    
    Write-ColorLog "  Insertions terminees" "Green"
} catch {
    Write-ColorLog "  ERREUR: $($_.Exception.Message)" "Red"
}

Write-ColorLog ""
Write-ColorLog "================================================================" "Green"
Write-ColorLog "           AUTOMATISATION TERMINEE" "Green"
Write-ColorLog "================================================================" "Green"
Write-ColorLog ""
Write-ColorLog "Application en cours (PID: $($script:AppProcess.Id))" "Cyan"
Write-ColorLog ""
Write-ColorLog "Appuyez sur Q pour quitter et arreter l'application..." "Yellow"
Write-ColorLog ""

# Boucle d'attente
while ($true) {
    if ($script:AppProcess.HasExited) {
        Write-ColorLog "Application arretee (code: $($script:AppProcess.ExitCode))" "Red"
        break
    }
    
    if ([Console]::KeyAvailable) {
        $key = [Console]::ReadKey($true)
        if ($key.Key -eq 'Q') {
            Stop-Application
        }
    }
    
    Start-Sleep -Milliseconds 500
}

Stop-Application
