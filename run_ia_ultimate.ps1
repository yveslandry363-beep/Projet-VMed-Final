<#
.SYNOPSIS
  run_ia_ultimate.ps1 - script de CI/CD local pour PrototypeGemini.
  Gère les dépendances, tests, build, exécution et analyse de logs.
.PARAMETER DryRun
  Exécute tout sauf 'dotnet run' (tests, format, build).
.PARAMETER Tail
  Nombre de lignes du log à afficher à la fin.
.PARAMETER UseContainer
  (Non implémenté) Builder et lancer via Docker.
#>

param(
    [switch]$DryRun = $false,
    [int]$Tail = 50,
    [switch]$UseContainer = $false
)

$ErrorActionPreference = 'Stop' # 1. Échouer rapidement
$global:stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
$projectPath = $PSScriptRoot
$logDir = Join-Path $PSScriptRoot "logs"
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir | Out-Null }
$logFile = Join-Path $logDir ("run_" + (Get-Date -Format "yyyyMMdd_HHmmss") + ".log")

# ... (Fonction Log inchangée) ...

function Log {
    param([string]$msg, [string]$level = "INFO")
    $line = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')][$level] $msg"
    $line | Out-File -FilePath $logFile -Append
    switch ($level) {
        "INFO" { Write-Host $line -ForegroundColor Cyan }
        "STATUS" { Write-Host $line -ForegroundColor Yellow }
        "SUCCESS" { Write-Host $line -ForegroundColor Green }
        "WARNING" { Write-Host $line -ForegroundColor DarkYellow }
        "ERROR" { Write-Host $line -ForegroundColor Red }
        default { Write-Host $line }
    }
}

# --- ÉTAPES DE VALIDATION ---
Log "Début du script. DryRun = $DryRun" "STATUS"

# 2. Chargement des variables d'environnement (.env)
$envFilePath = Join-Path $PSScriptRoot ".env"
if (Test-Path $envFilePath) {
    Log "Chargement du fichier .env..." "INFO"
    Get-Content $envFilePath | ForEach-Object {
        $name, $value = $_.Split('=', 2)
        if ($name -and $value) {
            [System.Environment]::SetEnvironmentVariable($name.Trim(), $value.Trim(), 'Process')
        }
    }
} else {
    Log ".env non trouvé. Vérifier que les variables (ENV:...) sont définies." "WARNING"
}

# (cspell.json check inchangé)

# 3. Étape de Formatage
Log "Vérification du formatage du code..." "STATUS"
dotnet format --verify-no-changes 2>&1 | Tee-Object -FilePath $logFile -Append
if ($LASTEXITCODE -ne 0) {
    Log "Problème de formatage. Exécutez 'dotnet format'." "ERROR"
    exit 4
}

# 4. Étape de Test (Pester)
Log "Exécution des tests (Pester/xUnit)..." "STATUS"
# (Supposons que les tests sont dans un projet .Tests)
dotnet test --logger "console;verbosity=minimal" 2>&1 | Tee-Object -FilePath $logFile -Append
if ($LASTEXITCODE -ne 0) {
    Log "Échec des tests unitaires." "ERROR"
    exit 5
}

# 5. Étape de Build
Log "Compilation du projet..." "STATUS"
dotnet build $projectPath 2>&1 | Tee-Object -FilePath $logFile -Append
if ($LASTEXITCODE -ne 0) {
    Log "Erreur de compilation." "ERROR"
    exit 3
}
Log "Compilation réussie." "SUCCESS"

if ($DryRun) {
    Log "Mode DryRun: arrêt après compilation." "INFO"
    exit 0
}

# --- ÉTAPE D'EXÉCUTION ---
Log "Exécution du projet (.NET run)..." "STATUS"
$global:runOutput = dotnet run --project $projectPath 2>&1 | Tee-Object -FilePath $logFile -Append
$global:stopwatch.Stop()

# --- ANALYSE DE SORTIE ---
Log "--- Analyse de la sortie ---" "STATUS"
$raw = Get-Content -Path $logFile -Raw -ErrorAction SilentlyContinue

# 6. Patterns de log fiables (basés sur les tags)
$patterns = @{
    victory = "\[VICTORY_API\]" # Succès
    noWork = "Message reçu \(offset" # Simple activité
    failApi = "\[FAIL_API\]"     # Erreur API
    failDb = "\[FAIL_DB\]"      # Erreur BDD
    failKafka = "\[FAIL_KAFKA\]"   # Erreur Kafka (DLQ)
}
$finalStatus = "unknown"

if ($raw -match $patterns.victory) {
    $finalStatus = "success"
    Log "FINALE: Processus terminé avec succès (Diagnostic traité)." "SUCCESS"
}
elseif ($raw -match $patterns.failApi) {
    $finalStatus = "api_error"
    Log "FINALE: Erreur API détectée. Vérifier logs [FAIL_API]." "ERROR"
}
elseif ($raw -match $patterns.failDb) {
    $finalStatus = "db_error"
    Log "FINALE: Erreur base de données détectée. Vérifier logs [FAIL_DB]." "ERROR"
}
elseif ($raw -match $patterns.failKafka) {
    $finalStatus = "kafka_error"
    Log "FINALE: Erreur Kafka (DLQ) détectée. Vérifier logs [FAIL_KAFKA]." "WARNING"
}
elseif ($raw -match $patterns.noWork) {
    $finalStatus = "processed_ok"
    Log "FINALE: Exécution normale (messages traités)." "INFO"
}
else {
    Log "FINALE: État indéterminé (pas de tag de statut majeur)." "ERROR"
}

Log ("Temps d'exécution total: {0} s" -f $global:stopwatch.Elapsed.TotalSeconds) "INFO"

# 7. Résumé JSON amélioré
$summary = @{
    timestamp = (Get-Date).ToString("o")
    durationSeconds = [math]::Round($global:stopwatch.Elapsed.TotalSeconds, 2)
    result = $finalStatus
}
$summaryPath = Join-Path $logDir "summary_" + (Get-Date -Format "yyyyMMdd_HHmmss") + ".json"
$summary | ConvertTo-Json | Out-File -FilePath $summaryPath -Encoding UTF8
Log "Résumé JSON écrit: $summaryPath" "INFO"

# ... (Tail du log inchangé) ...

Log "Fin du script." "STATUS"
exit 0