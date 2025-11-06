#!/usr/bin/env pwsh
# Script d'automatisation complète du prototype Gemini
# Auteur: Assistant AI
# Date: 2025-11-06
# Description: Lance l'application complète avec insertion automatique de données de test

param(
    [switch]$SkipBuild,
    [switch]$SkipInsert,
    [int]$InsertCount = 5,
    [int]$InsertIntervalSeconds = 10
)

$ErrorActionPreference = "Stop"
$script:AppProcess = $null
$script:LogFile = "logs/automation-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"

# Fonction de logging
function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    
    switch ($Level) {
        "ERROR" { Write-Host $logMessage -ForegroundColor Red }
        "WARN"  { Write-Host $logMessage -ForegroundColor Yellow }
        "SUCCESS" { Write-Host $logMessage -ForegroundColor Green }
        default { Write-Host $logMessage -ForegroundColor Cyan }
    }
    
    # Créer le dossier logs s'il n'existe pas
    $logsDir = Split-Path -Parent $script:LogFile
    if (-not (Test-Path $logsDir)) {
        New-Item -ItemType Directory -Path $logsDir -Force | Out-Null
    }
    
    Add-Content -Path $script:LogFile -Value $logMessage
}

# Fonction de nettoyage à l'arrêt
function Stop-Automation {
    Write-Log "🛑 Arrêt de l'automatisation..." "WARN"
    
    if ($script:AppProcess -and -not $script:AppProcess.HasExited) {
        Write-Log "Arrêt du processus dotnet (PID: $($script:AppProcess.Id))..." "WARN"
        Stop-Process -Id $script:AppProcess.Id -Force -ErrorAction SilentlyContinue
    }
    
    # Nettoyer tous les processus "Prototype Gemini"
    Get-Process | Where-Object { $_.ProcessName -like '*Prototype*' } | ForEach-Object {
        Write-Log "Nettoyage du processus restant: $($_.ProcessName) (PID: $($_.Id))" "WARN"
        Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
    }
    
    Write-Log "✅ Nettoyage terminé" "SUCCESS"
    exit 0
}

# Capturer Ctrl+C
Register-EngineEvent -SourceIdentifier PowerShell.Exiting -Action {
    Stop-Automation
} | Out-Null

# Bannière de démarrage
Clear-Host
Write-Host ""
Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║                                                              ║" -ForegroundColor Cyan
Write-Host "║        🚀 AUTOMATISATION COMPLÈTE - PROTOTYPE GEMINI 🚀      ║" -ForegroundColor Cyan
Write-Host "║                                                              ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

Write-Log "📋 Configuration:"
Write-Log "   - Répertoire: $(Get-Location)"
Write-Log "   - Build: $(if ($SkipBuild) { 'SKIP' } else { 'OUI' })"
Write-Log "   - Insertions auto: $(if ($SkipInsert) { 'NON' } else { "$InsertCount (intervalle: $InsertIntervalSeconds sec)" })"
Write-Log "   - Fichier log: $script:LogFile"
Write-Host ""

# ═══════════════════════════════════════════════════════════════
# ÉTAPE 1: Vérification de l'environnement
# ═══════════════════════════════════════════════════════════════
Write-Log "🔍 ÉTAPE 1/5: Vérification de l'environnement"

# Vérifier .NET
try {
    $dotnetVersion = dotnet --version
    Write-Log "✅ .NET SDK détecté: $dotnetVersion" "SUCCESS"
} catch {
    Write-Log "❌ .NET SDK introuvable. Installez .NET 9.0+ depuis https://dotnet.microsoft.com/download" "ERROR"
    exit 1
}

# Vérifier appsettings.json
if (-not (Test-Path "appsettings.json")) {
    Write-Log "❌ appsettings.json introuvable dans $(Get-Location)" "ERROR"
    exit 1
}
Write-Log "✅ appsettings.json trouvé" "SUCCESS"

# Vérifier gcp-key.json
if (-not (Test-Path "gcp-key.json")) {
    Write-Log "❌ gcp-key.json introuvable. OAuth2 Vertex AI ne fonctionnera pas." "ERROR"
    exit 1
}
Write-Log "✅ gcp-key.json trouvé" "SUCCESS"

if (-not (Test-Path "kafka_certs/ca.pem")) {
    Write-Log "(Certificats Kafka manquants dans kafka_certs/)" "WARN"
} else {
    Write-Log "✅ Certificats Kafka détectés" "SUCCESS"
}

Write-Host ""

# ═══════════════════════════════════════════════════════════════
# ÉTAPE 2: Build du projet
# ═══════════════════════════════════════════════════════════════
if (-not $SkipBuild) {
    Write-Log "🔨 ÉTAPE 2/5: Compilation du projet"
    
    try {
        $buildOutput = dotnet build --configuration Release 2>&1
        
        if ($LASTEXITCODE -ne 0) {
            Write-Log "❌ Échec de la compilation:" "ERROR"
            $buildOutput | ForEach-Object { Write-Log $_ "ERROR" }
            exit 1
        }
        
        Write-Log "✅ Compilation réussie" "SUCCESS"
        
        # Afficher les warnings s'il y en a
        $warnings = $buildOutput | Select-String -Pattern "warning"
        if ($warnings) {
            Write-Log "($($warnings.Count) avertissement(s) détecté(s))" "WARN"
        }
    } catch {
        Write-Log "❌ Erreur lors de la compilation: $($_.Exception.Message)" "ERROR"
        exit 1
    }
} else {
    Write-Log "ÉTAPE 2/5: Compilation ignorée (--SkipBuild)" "WARN"
}

Write-Host ""

# ═══════════════════════════════════════════════════════════════
# ÉTAPE 3: Nettoyage des processus existants
# ═══════════════════════════════════════════════════════════════
Write-Log "🧹 ÉTAPE 3/5: Nettoyage des processus existants"

$existingProcesses = Get-Process | Where-Object { $_.ProcessName -like '*Prototype*' }
if ($existingProcesses) {
    Write-Log "Arrêt de $($existingProcesses.Count) processus existant(s)..." "WARN"
    $existingProcesses | ForEach-Object {
        Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
        Write-Log "   Arrêté: $($_.ProcessName) (PID: $($_.Id))"
    }
    Start-Sleep -Seconds 2
}

Write-Log "✅ Nettoyage terminé" "SUCCESS"
Write-Host ""

# ═══════════════════════════════════════════════════════════════
# ÉTAPE 4: Démarrage de l'application
# ═══════════════════════════════════════════════════════════════
Write-Log "🚀 ÉTAPE 4/5: Démarrage de l'application"

try {
    # Démarrer l'application en arrière-plan
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "dotnet"
    $psi.Arguments = "run --configuration Release --no-build"
    $psi.WorkingDirectory = Get-Location
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $false
    
    $script:AppProcess = New-Object System.Diagnostics.Process
    $script:AppProcess.StartInfo = $psi
    
    # Capturer la sortie en temps réel
    $outputHandler = {
        if (-not [string]::IsNullOrEmpty($EventArgs.Data)) {
            Write-Log $EventArgs.Data
        }
    }
    
    Register-ObjectEvent -InputObject $script:AppProcess -EventName OutputDataReceived -Action $outputHandler | Out-Null
    Register-ObjectEvent -InputObject $script:AppProcess -EventName ErrorDataReceived -Action $outputHandler | Out-Null
    
    $script:AppProcess.Start() | Out-Null
    $script:AppProcess.BeginOutputReadLine()
    $script:AppProcess.BeginErrorReadLine()
    
    Write-Log "✅ Application démarrée (PID: $($script:AppProcess.Id))" "SUCCESS"
    Write-Log "⏳ Attente du démarrage complet (30 secondes)..."
    
    # Attendre que l'application soit prête
    $maxWait = 30
    $waited = 0
    while ($waited -lt $maxWait) {
        if ($script:AppProcess.HasExited) {
            Write-Log "❌ L'application s'est arrêtée prématurément (code: $($script:AppProcess.ExitCode))" "ERROR"
            exit 1
        }
        Start-Sleep -Seconds 1
        $waited++
        
        # Afficher une barre de progression
        $progress = [math]::Round(($waited / $maxWait) * 100)
        Write-Progress -Activity "Démarrage de l'application" -Status "$progress% complété" -PercentComplete $progress
    }
    
    Write-Progress -Activity "Démarrage de l'application" -Completed
    Write-Log "✅ Application démarrée et prête" "SUCCESS"
    
} catch {
    Write-Log "❌ Erreur lors du démarrage: $($_.Exception.Message)" "ERROR"
    exit 1
}

Write-Host ""

# ═══════════════════════════════════════════════════════════════
# ÉTAPE 5: Insertion automatique de données de test
# ═══════════════════════════════════════════════════════════════
if (-not $SkipInsert) {
    Write-Log "📝 ÉTAPE 5/5: Insertion automatique de données CDC"
    
    # Charger la chaîne de connexion
    try {
        $appsettings = Get-Content "appsettings.json" -Raw | ConvertFrom-Json
        $connectionString = $appsettings.PostgreSql.ConnectionString
        
        if (-not $connectionString) {
            Write-Log "❌ ConnectionString manquant dans appsettings.json" "ERROR"
            Stop-Automation
        }
        
        Write-Log "✅ Chaîne de connexion PostgreSQL chargée" "SUCCESS"
    } catch {
        Write-Log "❌ Erreur lors du chargement de appsettings.json: $($_.Exception.Message)" "ERROR"
        Stop-Automation
    }
    
    # Charger Npgsql
    try {
        $npgsqlDll = Get-ChildItem -Path ".\bin\Release\net9.0" -Filter "Npgsql.dll" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
        
        if (-not $npgsqlDll) {
            $npgsqlDll = Get-ChildItem -Path ".\bin\Debug\net9.0" -Filter "Npgsql.dll" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
        }
        
        if (-not $npgsqlDll) {
            Write-Log "❌ Npgsql.dll introuvable. Build requis." "ERROR"
            Stop-Automation
        }
        
        Add-Type -Path $npgsqlDll.FullName
        Write-Log "✅ Npgsql chargé depuis: $($npgsqlDll.FullName)" "SUCCESS"
    } catch {
        Write-Log "❌ Erreur lors du chargement de Npgsql: $($_.Exception.Message)" "ERROR"
        Stop-Automation
    }
    
    # Messages de test variés
    $testMessages = @(
        @{ Text = "Patient avec fièvre élevée (39.5°C) et toux persistante depuis 3 jours"; Guidance = "Analyse IA automatique - Test 1" },
        @{ Text = "Douleurs abdominales aiguës, localisation quadrant inférieur droit"; Guidance = "Analyse IA automatique - Test 2" },
        @{ Text = "Hypertension artérielle non contrôlée (180/110), patient diabétique de type 2"; Guidance = "Analyse IA automatique - Test 3" },
        @{ Text = "Céphalées sévères avec photophobie et vomissements"; Guidance = "Analyse IA automatique - Test 4" },
        @{ Text = "Dyspnée au repos, saturation en O2 à 88%, antécédents d'asthme"; Guidance = "Analyse IA automatique - Test 5" },
        @{ Text = "Suspicion de fracture du radius suite à une chute"; Guidance = "Analyse IA automatique - Test 6" },
        @{ Text = "Éruption cutanée généralisée avec prurit intense"; Guidance = "Analyse IA automatique - Test 7" },
        @{ Text = "Perte de conscience brève, confusion post-critique"; Guidance = "Analyse IA automatique - Test 8" },
        @{ Text = "Douleur thoracique rétrosternale irradiant au bras gauche"; Guidance = "Analyse IA automatique - Test 9" },
        @{ Text = "Polyurie, polydipsie, fatigue intense - glycémie à 18 mmol/L"; Guidance = "Analyse IA automatique - Test 10" }
    )
    
    Write-Log "🔄 Début des insertions (Total: $InsertCount, Intervalle: $InsertIntervalSeconds secondes)"
    Write-Host ""
    
    for ($i = 1; $i -le $InsertCount; $i++) {
        try {
            # Vérifier que l'application tourne toujours
            if ($script:AppProcess.HasExited) {
                Write-Log "❌ L'application s'est arrêtée (code: $($script:AppProcess.ExitCode))" "ERROR"
                break
            }
            
            # Choisir un message aléatoire
            $msg = $testMessages | Get-Random
            
            Write-Log "📤 Insertion $i/$InsertCount..."
            
            $conn = New-Object Npgsql.NpgsqlConnection($connectionString)
            $conn.Open()
            
            $sql = "INSERT INTO public.diagnostics (diagnostic_text, ia_guidance) VALUES (@text, @guidance) RETURNING id, date_creation;"
            
            $cmd = $conn.CreateCommand()
            $cmd.CommandText = $sql
            $null = $cmd.Parameters.AddWithValue("text", $msg.Text)
            $null = $cmd.Parameters.AddWithValue("guidance", $msg.Guidance)
            
            $reader = $cmd.ExecuteReader()
            
            if ($reader.Read()) {
                $insertedId = $reader.GetInt32(0)
                $dateCreation = $reader.GetDateTime(1)
                
                Write-Log "   ✅ ID=$insertedId | Date=$dateCreation" "SUCCESS"
                Write-Log "   📋 Texte: $($msg.Text.Substring(0, [Math]::Min(60, $msg.Text.Length)))..."
            }
            
            $reader.Close()
            $conn.Close()
            
            # Attendre avant la prochaine insertion (sauf pour la dernière)
            if ($i -lt $InsertCount) {
                Write-Log "   ⏳ Attente de $InsertIntervalSeconds secondes avant la prochaine insertion..."
                Start-Sleep -Seconds $InsertIntervalSeconds
            }
            
        } catch {
            Write-Log "❌ Erreur lors de l'insertion $i : $($_.Exception.Message)" "ERROR"
            
            if ($_.Exception.Message -like "*password*" -or $_.Exception.Message -like "*authentication*") {
                Write-Log "💡 Vérifiez les credentials PostgreSQL dans appsettings.json" "WARN"
            }
        }
    }
    
    Write-Host ""
    Write-Log "✅ Insertions terminées ($InsertCount/$InsertCount)" "SUCCESS"
    
} else {
    Write-Log "ÉTAPE 5/5: Insertions automatiques ignorées (--SkipInsert)" "WARN"
}

Write-Host ""
Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "║                                                              ║" -ForegroundColor Green
Write-Host "║              ✅ AUTOMATISATION COMPLÈTE RÉUSSIE ✅            ║" -ForegroundColor Green
Write-Host "║                                                              ║" -ForegroundColor Green
Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Green
Write-Host ""

Write-Log "📊 Résumé:"
Write-Log "   - Application: EN COURS (PID: $($script:AppProcess.Id))"
Write-Log "   - Insertions CDC: $InsertCount effectuée(s)"
Write-Log "   - Logs détaillés: $script:LogFile"
Write-Host ""

Write-Log "💡 L'application continue de tourner. Actions disponibles:" "INFO"
Write-Host ""
Write-Host "   [I] Insérer un nouveau diagnostic manuellement" -ForegroundColor Cyan
Write-Host "   [A] Lancer une série d'insertions automatiques" -ForegroundColor Cyan
Write-Host "   [L] Afficher les logs en temps réel" -ForegroundColor Cyan
Write-Host "   [S] Afficher les statistiques" -ForegroundColor Cyan
Write-Host "   [Q] Quitter et arrêter l'application" -ForegroundColor Yellow
Write-Host ""

# Boucle interactive
while ($true) {
    try {
        # Vérifier si l'application tourne toujours
        if ($script:AppProcess.HasExited) {
            Write-Log "❌ L'application s'est arrêtée (code: $($script:AppProcess.ExitCode))" "ERROR"
            break
        }
        
        Write-Host "Votre choix: " -NoNewline -ForegroundColor White
        $choice = Read-Host
        
        switch ($choice.ToUpper()) {
            "I" {
                Write-Host ""
                Write-Host "Texte du diagnostic: " -NoNewline -ForegroundColor Cyan
                $text = Read-Host
                
                if ([string]::IsNullOrWhiteSpace($text)) {
                    Write-Log "❌ Texte vide, opération annulée" "WARN"
                    continue
                }
                
                try {
                    $conn = New-Object Npgsql.NpgsqlConnection($connectionString)
                    $conn.Open()
                    
                    $sql = "INSERT INTO public.diagnostics (diagnostic_text, ia_guidance) VALUES (@text, @guidance) RETURNING id;"
                    $cmd = $conn.CreateCommand()
                    $cmd.CommandText = $sql
                    $null = $cmd.Parameters.AddWithValue("text", $text)
                    $null = $cmd.Parameters.AddWithValue("guidance", "Insertion manuelle via automatisation")
                    
                    $id = $cmd.ExecuteScalar()
                    $conn.Close()
                    
                    Write-Log "✅ Diagnostic inséré avec ID=$id" "SUCCESS"
                } catch {
                    Write-Log "❌ Erreur: $($_.Exception.Message)" "ERROR"
                }
            }
            
            "A" {
                Write-Host ""
                Write-Host "Nombre d'insertions: " -NoNewline -ForegroundColor Cyan
                $count = Read-Host
                
                if ([string]::IsNullOrWhiteSpace($count) -or -not ($count -as [int])) {
                    Write-Log "❌ Nombre invalide" "WARN"
                    continue
                }
                
                Write-Host "Intervalle (secondes): " -NoNewline -ForegroundColor Cyan
                $interval = Read-Host
                
                if ([string]::IsNullOrWhiteSpace($interval) -or -not ($interval -as [int])) {
                    $interval = 5
                }
                
                Write-Log "🔄 Lancement de $count insertions (intervalle: $interval sec)..."
                
                for ($j = 1; $j -le [int]$count; $j++) {
                    $msg = $testMessages | Get-Random
                    
                    try {
                        $conn = New-Object Npgsql.NpgsqlConnection($connectionString)
                        $conn.Open()
                        
                        $sql = "INSERT INTO public.diagnostics (diagnostic_text, ia_guidance) VALUES (@text, @guidance) RETURNING id;"
                        $cmd = $conn.CreateCommand()
                        $cmd.CommandText = $sql
                        $null = $cmd.Parameters.AddWithValue("text", $msg.Text)
                        $null = $cmd.Parameters.AddWithValue("guidance", "Auto batch $j/$count")
                        
                        $id = $cmd.ExecuteScalar()
                        $conn.Close()
                        
                        Write-Log "✅ [$j/$count] ID=$id | $($msg.Text.Substring(0, [Math]::Min(50, $msg.Text.Length)))..." "SUCCESS"
                        
                        if ($j -lt [int]$count) {
                            Start-Sleep -Seconds ([int]$interval)
                        }
                    } catch {
                        Write-Log "❌ Erreur insertion $j : $($_.Exception.Message)" "ERROR"
                    }
                }
                
                Write-Log "✅ Batch terminé" "SUCCESS"
            }
            
            "L" {
                Write-Host ""
                Write-Log "📄 Affichage des 20 dernières lignes du log..."
                if (Test-Path $script:LogFile) {
                    Get-Content $script:LogFile -Tail 20 | ForEach-Object { Write-Host $_ }
                } else {
                    Write-Log "❌ Fichier log introuvable" "WARN"
                }
            }
            
            "S" {
                Write-Host ""
                Write-Log "📊 Statistiques de l'application:"
                Write-Log "   - PID: $($script:AppProcess.Id)"
                Write-Log "   - Temps d'exécution: $([math]::Round(((Get-Date) - $script:AppProcess.StartTime).TotalMinutes, 2)) minutes"
                
                try {
                    $process = Get-Process -Id $script:AppProcess.Id
                    Write-Log "   - Mémoire utilisée: $([math]::Round($process.WorkingSet64 / 1MB, 2)) MB"
                    Write-Log "   - Threads: $($process.Threads.Count)"
                } catch {
                    Write-Log "   (Impossible de récupérer les statistiques)" "WARN"
                }
            }
            
            "Q" {
                Write-Host ""
                Write-Log "👋 Arrêt de l'automatisation..." "WARN"
                Stop-Automation
            }
            
            default {
                Write-Log "❌ Choix invalide. Utilisez I, A, L, S ou Q" "WARN"
            }
        }
        
        Write-Host ""
        
    } catch {
        Write-Log "❌ Erreur: $($_.Exception.Message)" "ERROR"
    }
}

# Ne devrait jamais arriver ici, mais au cas où
Stop-Automation
