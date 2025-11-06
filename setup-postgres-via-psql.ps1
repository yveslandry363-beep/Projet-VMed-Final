# ═══════════════════════════════════════════════════════════════════
# Script PowerShell - Configuration PostgreSQL Aiven pour Debezium
# Exécute le SQL automatiquement sans DBeaver
# ═══════════════════════════════════════════════════════════════════

Write-Host "🚀 Configuration PostgreSQL Aiven pour Debezium CDC" -ForegroundColor Cyan
Write-Host ("=" * 70) -ForegroundColor Cyan

# Configuration PostgreSQL Aiven
$PG_HOST = "ia-postgres-db-yveslandry363-974a.g.aivencloud.com"
$PG_PORT = "15593"
$PG_USER = "avnadmin"
$PG_DB = "defaultdb"

# Demander le mot de passe
Write-Host "`n🔐 Entrez votre mot de passe PostgreSQL Aiven:" -ForegroundColor Yellow
$PG_PASSWORD = Read-Host -AsSecureString
$PG_PASSWORD_PLAIN = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
    [Runtime.InteropServices.Marshal]::SecureStringToBSTR($PG_PASSWORD)
)

# Vérifier si psql est installé
Write-Host "`n🔍 Vérification de psql..." -ForegroundColor Cyan
$psqlPath = Get-Command psql -ErrorAction SilentlyContinue

if (-not $psqlPath) {
    Write-Host "❌ psql n'est pas installé ou pas dans le PATH" -ForegroundColor Red
    Write-Host "`n💡 Solutions:" -ForegroundColor Yellow
    Write-Host "   1. Utilisez DBeaver (plus simple):" -ForegroundColor Gray
    Write-Host "      - Ouvrez DBeaver" -ForegroundColor Gray
    Write-Host "      - Connectez-vous à PostgreSQL Aiven" -ForegroundColor Gray
    Write-Host "      - Exécutez le fichier: setup-aiven-postgres.sql" -ForegroundColor Gray
    Write-Host "`n   2. Installez PostgreSQL client:" -ForegroundColor Gray
    Write-Host "      - Téléchargez depuis: https://www.postgresql.org/download/windows/" -ForegroundColor Gray
    Write-Host "      - Ou via Chocolatey: choco install postgresql" -ForegroundColor Gray
    exit 1
}

Write-Host "✅ psql trouvé: $($psqlPath.Source)" -ForegroundColor Green

# Créer le script SQL temporaire
$sqlScript = @"
-- ═══════════════════════════════════════════════════════════════════
-- Configuration PostgreSQL pour Debezium CDC
-- ═══════════════════════════════════════════════════════════════════

-- 1. CRÉER LA TABLE DIAGNOSTICS
CREATE TABLE IF NOT EXISTS public.diagnostics (
    id SERIAL PRIMARY KEY,
    diagnostic_text TEXT NOT NULL,
    ia_guidance TEXT,
    date_creation TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    created_by VARCHAR(100) DEFAULT CURRENT_USER,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- 2. CONFIGURER POUR DEBEZIUM CDC
ALTER TABLE public.diagnostics REPLICA IDENTITY FULL;

CREATE INDEX IF NOT EXISTS idx_diagnostics_date_creation 
    ON public.diagnostics (date_creation DESC);

-- 3. CRÉER LA PUBLICATION DEBEZIUM
DROP PUBLICATION IF EXISTS dbz_publication;
CREATE PUBLICATION dbz_publication FOR TABLE public.diagnostics;

-- 4. DONNÉES DE TEST
INSERT INTO public.diagnostics (diagnostic_text, ia_guidance) 
VALUES ('Patient présente des symptômes de grippe saisonnière', 
        'Repos, hydratation, paracétamol si fièvre. Consulter si aggravation.')
ON CONFLICT DO NOTHING;

-- 5. VÉRIFICATIONS
SELECT 'Table créée:' AS info, tablename 
FROM pg_tables 
WHERE tablename = 'diagnostics';

SELECT 'Publication créée:' AS info, pubname 
FROM pg_publication 
WHERE pubname = 'dbz_publication';

SELECT 'REPLICA IDENTITY:' AS info, 
    CASE relreplident
        WHEN 'f' THEN 'FULL ✅'
        ELSE relreplident
    END AS status
FROM pg_class 
WHERE relname = 'diagnostics';

SELECT 'Nombre de diagnostics:' AS info, COUNT(*) AS count
FROM public.diagnostics;
"@

# Sauvegarder le script SQL
$tempSqlFile = Join-Path $PSScriptRoot "temp_setup.sql"
$sqlScript | Out-File -FilePath $tempSqlFile -Encoding UTF8

Write-Host "`n📝 Script SQL créé: $tempSqlFile" -ForegroundColor Cyan

# Construire la connection string
$env:PGPASSWORD = $PG_PASSWORD_PLAIN
$connectionString = "host=$PG_HOST port=$PG_PORT dbname=$PG_DB user=$PG_USER sslmode=require"

# Exécuter le script SQL
Write-Host "`n🔄 Exécution du script SQL sur PostgreSQL Aiven..." -ForegroundColor Cyan
Write-Host "   Host: $PG_HOST" -ForegroundColor Gray
Write-Host "   Port: $PG_PORT" -ForegroundColor Gray
Write-Host "   Database: $PG_DB" -ForegroundColor Gray
Write-Host "   User: $PG_USER" -ForegroundColor Gray

try {
    $result = & psql "$connectionString" -f $tempSqlFile 2>&1
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "`n✅ Script exécuté avec succès!" -ForegroundColor Green
        Write-Host "`n📊 Résultats:" -ForegroundColor Cyan
        Write-Host $result -ForegroundColor Gray
    } else {
        Write-Host "`n❌ Erreur lors de l'exécution" -ForegroundColor Red
        Write-Host $result -ForegroundColor Yellow
        exit 1
    }
} catch {
    Write-Host "`n❌ Erreur: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
} finally {
    # Nettoyer
    Remove-Item $tempSqlFile -ErrorAction SilentlyContinue
    $env:PGPASSWORD = $null
}

Write-Host "`n" + ("=" * 70) -ForegroundColor Cyan
Write-Host "✅ Configuration PostgreSQL terminée!" -ForegroundColor Green
Write-Host "`n🎯 Prochaine étape:" -ForegroundColor Yellow
Write-Host "   Allez sur https://console.aiven.io" -ForegroundColor Gray
Write-Host "   Configurez le connecteur Debezium avec debezium-aiven-connector-config.json" -ForegroundColor Gray
Write-Host ("=" * 70) -ForegroundColor Cyan
