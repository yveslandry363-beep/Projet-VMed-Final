#!/usr/bin/env pwsh
# Script d'automatisation simplifie - Prototype Gemini

param([int]$TestInserts = 3)

Write-Host ""
Write-Host "=== AUTOMATISATION PROTOTYPE GEMINI ===" -ForegroundColor Cyan
Write-Host ""

# Etape 1: Build
Write-Host "[1/4] Build..." -ForegroundColor Yellow
dotnet build -c Release
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERREUR: Build echoue" -ForegroundColor Red
    exit 1
}
Write-Host "Build OK" -ForegroundColor Green
Write-Host ""

# Etape 2: Cleanup
Write-Host "[2/4] Nettoyage..." -ForegroundColor Yellow
Get-Process | Where-Object { $_.ProcessName -like '*Prototype*' } | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2
Write-Host "Nettoyage OK" -ForegroundColor Green
Write-Host ""

# Etape 3: Demarrer l'app en arriere-plan
Write-Host "[3/4] Demarrage application..." -ForegroundColor Yellow
$job = Start-Job -ScriptBlock {
    Set-Location $using:PWD
    dotnet run -c Release --no-build 2>&1
}

Write-Host "Application demarree (Job ID: $($job.Id))" -ForegroundColor Green
Write-Host "Attente initialisation (35 sec)..." -ForegroundColor Yellow
Start-Sleep -Seconds 35

# Verifier que le job tourne
if ($job.State -ne 'Running') {
    Write-Host "ERREUR: Application non demarree correctement" -ForegroundColor Red
    Write-Host ""
    Write-Host "Sortie du job:" -ForegroundColor Yellow
    Receive-Job -Job $job
    Remove-Job -Job $job -Force
    exit 1
}

Write-Host "Application prete" -ForegroundColor Green
Write-Host ""

# Etape 4: Insertions
Write-Host "[4/4] Insertions CDC automatiques ($TestInserts)..." -ForegroundColor Yellow

try {
    # Charger config
    $config = Get-Content "appsettings.json" -Raw | ConvertFrom-Json
    $connStr = $config.PostgreSql.ConnectionString
    
    # Charger Npgsql
    $npgsql = Get-ChildItem -Path ".\bin\Release\net9.0" -Filter "Npgsql.dll" -Recurse | Select-Object -First 1
    if (-not $npgsql) {
        $npgsql = Get-ChildItem -Path ".\bin\Debug\net9.0" -Filter "Npgsql.dll" -Recurse | Select-Object -First 1
    }
    Add-Type -Path $npgsql.FullName
    
    $diagnostics = @(
        "Patient avec fievre elevee (39C) et toux depuis 3 jours",
        "Douleurs abdominales aigues, quadrant inferieur droit",
        "Hypertension 180/110, patient diabetique type 2",
        "Cephalees severes avec photophobie et vomissements",
        "Dyspnee au repos, saturation O2 a 88%, asthme"
    )
    
    for ($i = 1; $i -le $TestInserts; $i++) {
        $msg = $diagnostics | Get-Random
        
        $conn = New-Object Npgsql.NpgsqlConnection($connStr)
        $conn.Open()
        
        $cmd = $conn.CreateCommand()
        $cmd.CommandText = "INSERT INTO public.diagnostics (diagnostic_text, ia_guidance) VALUES (@txt, @guid) RETURNING id"
        $null = $cmd.Parameters.AddWithValue("txt", $msg)
        $null = $cmd.Parameters.AddWithValue("guid", "Auto CDC test $i")
        
        $id = $cmd.ExecuteScalar()
        
        $conn.Close()
        
        Write-Host "  [$i/$TestInserts] ID=$id | $($msg.Substring(0, [Math]::Min(50, $msg.Length)))..." -ForegroundColor Green
        
        if ($i -lt $TestInserts) {
            Write-Host "           Attente 8 sec..." -ForegroundColor DarkGray
            Start-Sleep -Seconds 8
        }
    }
    
    Write-Host ""
    Write-Host "Insertions terminees" -ForegroundColor Green
    
} catch {
    Write-Host "ERREUR insertions: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""
Write-Host "=== AUTOMATISATION TERMINEE ===" -ForegroundColor Green
Write-Host ""
Write-Host "L'application continue de tourner." -ForegroundColor Cyan
Write-Host "Consultez les logs de l'app:" -ForegroundColor Yellow
Write-Host ""

# Afficher les 15 dernieres lignes du job
$output = Receive-Job -Job $job -Keep
$lines = $output -split "`n"
$lastLines = $lines | Select-Object -Last 15

Write-Host "--- Dernieres lignes de l'application ---" -ForegroundColor Cyan
$lastLines | ForEach-Object { Write-Host $_ }
Write-Host "--- Fin des logs ---" -ForegroundColor Cyan
Write-Host ""

Write-Host "Commandes disponibles:" -ForegroundColor Yellow
Write-Host "  - Voir tous les logs:  Receive-Job -Job $($job.Id)" -ForegroundColor White
Write-Host "  - Arreter l'app:       Stop-Job -Job $($job.Id); Remove-Job -Job $($job.Id)" -ForegroundColor White
Write-Host ""
Write-Host "Appuyez sur Entree pour arreter l'application et quitter..." -ForegroundColor Yellow
Read-Host

# Cleanup
Write-Host "Arret de l'application..." -ForegroundColor Yellow
Stop-Job -Job $job -ErrorAction SilentlyContinue
Remove-Job -Job $job -Force -ErrorAction SilentlyContinue

Write-Host "Termine" -ForegroundColor Green
