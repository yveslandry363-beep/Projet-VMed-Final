# Script de configuration PostgreSQL pour Debezium CDC
# Auteur: Configuration automatique
# Date: 2025-11-06

Write-Host "🚀 Configuration PostgreSQL pour Debezium CDC" -ForegroundColor Cyan
Write-Host "=" * 60 -ForegroundColor Cyan

# Chargement de la configuration depuis appsettings.json
$config = Get-Content "appsettings.json" | ConvertFrom-Json
$pgHost = "ia-postgres-db-yveslandry363-974a.g.aivencloud.com"
$pgPort = "15593"
$pgUser = "avnadmin"
$pgPassword = "AVNS_y_YB7yKdoi-r20UAu1z"
$pgDatabase = "defaultdb"

Write-Host "`n📋 Configuration détectée:" -ForegroundColor Yellow
Write-Host "   Host: $pgHost" -ForegroundColor Gray
Write-Host "   Port: $pgPort" -ForegroundColor Gray
Write-Host "   User: $pgUser" -ForegroundColor Gray
Write-Host "   Database: $pgDatabase" -ForegroundColor Gray

# Créer le fichier SQL de configuration
$sqlScript = @"
-- =============================================================================
-- Configuration Debezium CDC pour PostgreSQL
-- Généré automatiquement le $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
-- =============================================================================

-- 1. Créer la publication pour toutes les tables du schéma public
DO `$`$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'dbz_publication') THEN
        CREATE PUBLICATION dbz_publication FOR ALL TABLES;
        RAISE NOTICE '✅ Publication dbz_publication créée avec succès';
    ELSE
        RAISE NOTICE '⚠️  Publication dbz_publication existe déjà';
    END IF;
END
`$`$;

-- 2. Vérifier et activer la réplication pour l'utilisateur avnadmin
DO `$`$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'avnadmin' AND rolreplication = true) THEN
        ALTER ROLE avnadmin WITH REPLICATION;
        RAISE NOTICE '✅ Réplication activée pour avnadmin';
    ELSE
        RAISE NOTICE '⚠️  Réplication déjà active pour avnadmin';
    END IF;
END
`$`$;

-- 3. Donner les permissions nécessaires
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO avnadmin;
GRANT USAGE ON SCHEMA public TO avnadmin;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO avnadmin;

-- 4. Créer le slot de réplication logique (si pas déjà existant)
DO `$`$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_replication_slots WHERE slot_name = 'debezium_slot') THEN
        PERFORM pg_create_logical_replication_slot('debezium_slot', 'pgoutput');
        RAISE NOTICE '✅ Slot de réplication debezium_slot créé';
    ELSE
        RAISE NOTICE '⚠️  Slot debezium_slot existe déjà';
    END IF;
END
`$`$;

-- 5. Créer la table diagnostics si elle n'existe pas
CREATE TABLE IF NOT EXISTS public.diagnostics (
    id SERIAL PRIMARY KEY,
    patient_id VARCHAR(100),
    diagnostic_text TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    status VARCHAR(50) DEFAULT 'pending'
);

-- 6. Activer la réplication pour la table diagnostics
ALTER TABLE public.diagnostics REPLICA IDENTITY FULL;

-- 7. Vérifications finales
SELECT 
    '📊 État de la configuration Debezium' as info,
    (SELECT count(*) FROM pg_publication WHERE pubname = 'dbz_publication') as publications,
    (SELECT count(*) FROM pg_replication_slots WHERE slot_name = 'debezium_slot') as slots,
    (SELECT rolreplication FROM pg_roles WHERE rolname = 'avnadmin') as replication_enabled;

-- Afficher les publications
\echo '📋 Publications configurées:'
SELECT pubname, puballtables FROM pg_publication WHERE pubname = 'dbz_publication';

-- Afficher les slots de réplication
\echo '🔌 Slots de réplication:'
SELECT slot_name, plugin, slot_type, active FROM pg_replication_slots WHERE slot_name = 'debezium_slot';

-- Afficher les tables répliquées
\echo '📦 Tables dans la publication:'
SELECT schemaname, tablename FROM pg_publication_tables WHERE pubname = 'dbz_publication';

\echo '✅ Configuration Debezium terminée avec succès!'
"@

# Sauvegarder le script SQL
$sqlFile = "setup-debezium.sql"
$sqlScript | Out-File -FilePath $sqlFile -Encoding UTF8
Write-Host "`n✅ Script SQL généré: $sqlFile" -ForegroundColor Green

# Construire la chaîne de connexion PostgreSQL
$env:PGPASSWORD = $pgPassword

Write-Host "`n🔄 Exécution du script SQL sur PostgreSQL..." -ForegroundColor Cyan

# Vérifier si psql est installé
$psqlPath = Get-Command psql -ErrorAction SilentlyContinue

if ($psqlPath) {
    Write-Host "   psql trouvé: $($psqlPath.Source)" -ForegroundColor Gray
    
    # Exécuter le script SQL
    & psql -h $pgHost -p $pgPort -U $pgUser -d $pgDatabase -f $sqlFile
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "`n✅ Configuration PostgreSQL réussie!" -ForegroundColor Green
    } else {
        Write-Host "`n❌ Erreur lors de l'exécution du script SQL (code: $LASTEXITCODE)" -ForegroundColor Red
        Write-Host "   Vérifiez que PostgreSQL est accessible et que les credentials sont corrects" -ForegroundColor Yellow
    }
} else {
    Write-Host "`n⚠️  psql (PostgreSQL client) n'est pas installé sur ce système" -ForegroundColor Yellow
    Write-Host "`n📝 Instructions manuelles:" -ForegroundColor Cyan
    Write-Host "   1. Installez PostgreSQL client: https://www.postgresql.org/download/windows/" -ForegroundColor Gray
    Write-Host "   2. Ou exécutez manuellement le fichier: $sqlFile" -ForegroundColor Gray
    Write-Host "   3. Commande: psql -h $pgHost -p $pgPort -U $pgUser -d $pgDatabase -f $sqlFile" -ForegroundColor Gray
}

# Nettoyer la variable d'environnement du mot de passe
Remove-Item Env:\PGPASSWORD -ErrorAction SilentlyContinue

Write-Host "`n" + ("=" * 60) -ForegroundColor Cyan
Write-Host "✅ Script terminé" -ForegroundColor Green
Write-Host ("=" * 60) -ForegroundColor Cyan
