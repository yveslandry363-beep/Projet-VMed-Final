# Script: test-cdc-insertion.ps1
# Teste l'insertion CDC en temps réel depuis PowerShell

Write-Host "🧪 TEST D'INSERTION CDC DEBEZIUM" -ForegroundColor Cyan
Write-Host ("=" * 70)

Write-Host "`n📋 Connexion à PostgreSQL Aiven..." -ForegroundColor Yellow

# Préférence: lire la chaîne de connexion directement depuis appsettings.json
$appsettingsPath = Join-Path (Get-Location) 'appsettings.json'
if (Test-Path $appsettingsPath) {
    try {
        $json = Get-Content $appsettingsPath -Raw | ConvertFrom-Json
        $connectionString = $json.PostgreSql.ConnectionString
        Write-Host "🔐 Chaîne de connexion lue depuis appsettings.json" -ForegroundColor DarkCyan
    } catch {
        Write-Host "⚠️  Impossible de lire appsettings.json, utilisation des valeurs par défaut du script." -ForegroundColor Yellow
    }
}

if (-not $connectionString) {
    # Secours: valeurs codées (à éviter en prod)
    $connectionString = "Host=ia-postgres-db-yveslandry363-974a.h.aivencloud.com;" +
                       "Port=15593;" +
                       "Database=defaultdb;" +
                       "Username=avnadmin;" +
                       "Password=VOTRE_MOT_DE_PASSE_ICI;" +  # ⚠️ REMPLACEZ ICI si appsettings absent
                       "SSL Mode=Require;" +
                       "Trust Server Certificate=true;"
}

Write-Host "⚠️  ATTENTION: Ce script nécessite Npgsql" -ForegroundColor Red
Write-Host "Installez avec: dotnet add package Npgsql`n"

try {
    # Charger Npgsql (depuis le projet)
    $npgsqlDll = Get-ChildItem -Path ".\bin\Debug\net9.0" -Filter "Npgsql.dll" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $npgsqlDll) {
        # Essayer dans obj ou packages restauration locale
        $npgsqlDll = Get-ChildItem -Path "." -Filter "Npgsql.dll" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    }
    
    if (-not $npgsqlDll) {
        throw "Npgsql.dll introuvable. Compilez d'abord le projet avec 'dotnet build'"
    }
    
    Add-Type -Path $npgsqlDll.FullName
    
    Write-Host "✅ Npgsql chargé depuis: $($npgsqlDll.FullName)`n" -ForegroundColor Green
    
    # Connexion à PostgreSQL
    $conn = New-Object Npgsql.NpgsqlConnection($connectionString)
    $conn.Open()
    
    Write-Host "✅ Connecté à PostgreSQL Aiven!`n" -ForegroundColor Green
    
    # Générer des données de test
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $diagnosticText = "Test CDC temps réel - $timestamp"
    $iaGuidance = "Validation complète du flux Debezium → Kafka → C# Application"
    
    Write-Host "📝 Insertion du diagnostic..." -ForegroundColor Yellow
    Write-Host "   Texte: $diagnosticText"
    Write-Host "   Guidance: $iaGuidance`n"
    
    # Insertion SQL
    $sql = @"
INSERT INTO public.diagnostics (diagnostic_text, ia_guidance) 
VALUES (@text, @guidance)
RETURNING id, date_creation;
"@
    
    $cmd = $conn.CreateCommand()
    $cmd.CommandText = $sql
    $cmd.Parameters.AddWithValue("text", $diagnosticText) | Out-Null
    $cmd.Parameters.AddWithValue("guidance", $iaGuidance) | Out-Null
    
    $reader = $cmd.ExecuteReader()
    
    if ($reader.Read()) {
        $insertedId = $reader.GetInt32(0)
        $dateCreation = $reader.GetDateTime(1)
        
        Write-Host "✅ INSERTION RÉUSSIE!" -ForegroundColor Green
        Write-Host "   ID: $insertedId"
        Write-Host "   Date: $dateCreation"
    }
    
    $reader.Close()
    $conn.Close()
    
    Write-Host "`n" ("=" * 70)
    Write-Host "🎯 PROCHAINES ÉTAPES:" -ForegroundColor Cyan
    Write-Host ("=" * 70)
    Write-Host "1. Vérifiez la console C# (dotnet run)"
    Write-Host "   Vous devriez voir:"
    Write-Host "   [INF] 📬 Message Debezium reçu: Op=c, ID=$insertedId, Text=Test CDC..." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "2. Vérifiez Aiven Console → Topics → pg_diagnostics.public.diagnostics"
    Write-Host "   Le message CDC doit apparaître en quelques secondes"
    Write-Host ""
    Write-Host "3. Si rien n'apparaît, vérifiez:"
    Write-Host "   - Debezium connector status (doit être RUNNING)"
    Write-Host "   - Publication dbz_publication existe"
    Write-Host "   - Replication slot actif"
    Write-Host ""
    
    Write-Host "✅ Test CDC terminé avec succès!" -ForegroundColor Green
    
} catch {
    Write-Host "`n❌ ERREUR: $($_.Exception.Message)" -ForegroundColor Red
    
    if ($_.Exception.Message -like "*password*" -or $_.Exception.Message -like "*authentication*") {
        Write-Host "`n💡 Vérifiez que vous avez remplacé 'VOTRE_MOT_DE_PASSE_ICI' par votre vrai mot de passe PostgreSQL" -ForegroundColor Yellow
    }
    
    if ($_.Exception.Message -like "*Npgsql*") {
        Write-Host "`n💡 Compilez d'abord le projet: dotnet build" -ForegroundColor Yellow
    }
    
    exit 1
}

Write-Host "`nAppuyez sur une touche pour quitter..."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
