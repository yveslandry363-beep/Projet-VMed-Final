-- ═══════════════════════════════════════════════════════════════════
-- TEST D'INSERTION CDC DEBEZIUM - À exécuter dans DBeaver
-- ═══════════════════════════════════════════════════════════════════

-- 1. Vérifiez d'abord la connexion PostgreSQL
SELECT 
    current_database() as database_name,
    current_user as user_name,
    version() as pg_version,
    NOW() as current_time;

-- 2. Vérifiez que la table existe
SELECT 
    COUNT(*) as total_diagnostics,
    MAX(id) as last_id
FROM public.diagnostics;

-- 3. Vérifiez que la publication Debezium existe
SELECT 
    pubname,
    puballtables,
    pubinsert,
    pubupdate,
    pubdelete
FROM pg_publication
WHERE pubname = 'dbz_publication';

-- 4. Vérifiez que la table a REPLICA IDENTITY FULL
SELECT 
    relname,
    relreplident
FROM pg_class
WHERE relname = 'diagnostics';
-- Résultat attendu: relreplident = 'f' (FULL)

-- ═══════════════════════════════════════════════════════════════════
-- 🧪 TEST 1: Insertion simple
-- ═══════════════════════════════════════════════════════════════════

INSERT INTO public.diagnostics (diagnostic_text, ia_guidance) 
VALUES (
    'Test CDC #1 - Insertion simple - ' || NOW(),
    'Validation flux Debezium → Kafka → C# Application'
)
RETURNING 
    id,
    diagnostic_text,
    ia_guidance,
    date_creation,
    created_by;

-- Attendez 2-3 secondes et vérifiez la console C# pour:
-- [INF] 📬 Message Debezium reçu: Op=c, ID=X, Text=Test CDC #1...

-- ═══════════════════════════════════════════════════════════════════
-- 🧪 TEST 2: Insertion avec données médicales réalistes
-- ═══════════════════════════════════════════════════════════════════

INSERT INTO public.diagnostics (diagnostic_text, ia_guidance) 
VALUES (
    'Patient présente fièvre (38.5°C), toux sèche, fatigue depuis 3 jours. Pas de difficultés respiratoires.',
    'Syndrome grippal probable. Repos, hydratation, paracétamol 1g 3x/jour. Consulter si aggravation ou dyspnée.'
)
RETURNING 
    id,
    diagnostic_text,
    date_creation;

-- ═══════════════════════════════════════════════════════════════════
-- 🧪 TEST 3: Test de sécurité - Tentative d'injection SQL (DEVRAIT ÊTRE BLOQUÉE)
-- ═══════════════════════════════════════════════════════════════════

INSERT INTO public.diagnostics (diagnostic_text, ia_guidance) 
VALUES (
    'SELECT * FROM users WHERE 1=1; DROP TABLE diagnostics;--',
    'Test de sécurité anti-injection SQL'
)
RETURNING id, diagnostic_text;

-- Résultat attendu dans la console C#:
-- [ERR] 🚨 TENTATIVE D'ATTAQUE DÉTECTÉE : Le diagnostic contient des caractères suspects (possible injection SQL) - Diagnostic ID X

-- ═══════════════════════════════════════════════════════════════════
-- 🧪 TEST 4: Update (si supporté par Debezium)
-- ═══════════════════════════════════════════════════════════════════

-- Récupérez l'ID du dernier diagnostic
WITH last_diag AS (
    SELECT id FROM public.diagnostics ORDER BY id DESC LIMIT 1
)
UPDATE public.diagnostics 
SET 
    ia_guidance = 'Guidance mise à jour - ' || NOW(),
    updated_at = NOW()
WHERE id = (SELECT id FROM last_diag)
RETURNING id, diagnostic_text, ia_guidance, updated_at;

-- Résultat attendu:
-- [INF] 📬 Message Debezium reçu: Op=u, ID=X, Text=...

-- ═══════════════════════════════════════════════════════════════════
-- 🧪 TEST 5: Delete (soft delete avec __deleted flag)
-- ═══════════════════════════════════════════════════════════════════

-- NOTE: Ne pas vraiment supprimer en production !
-- Ceci générera un événement Debezium 'op=d'
/*
WITH last_diag AS (
    SELECT id FROM public.diagnostics ORDER BY id DESC LIMIT 1
)
DELETE FROM public.diagnostics 
WHERE id = (SELECT id FROM last_diag)
RETURNING id;
*/

-- ═══════════════════════════════════════════════════════════════════
-- 📊 VÉRIFICATIONS POST-TEST
-- ═══════════════════════════════════════════════════════════════════

-- Voir tous les diagnostics récents
SELECT 
    id,
    LEFT(diagnostic_text, 50) || '...' as diagnostic_preview,
    LEFT(ia_guidance, 50) || '...' as guidance_preview,
    date_creation,
    created_by,
    updated_at
FROM public.diagnostics
ORDER BY id DESC
LIMIT 10;

-- Statistiques
SELECT 
    COUNT(*) as total_records,
    COUNT(CASE WHEN ia_guidance IS NOT NULL THEN 1 END) as with_guidance,
    COUNT(CASE WHEN ia_guidance IS NULL THEN 1 END) as without_guidance,
    MIN(date_creation) as first_record,
    MAX(date_creation) as last_record
FROM public.diagnostics;

-- ═══════════════════════════════════════════════════════════════════
-- 🎯 COMMANDES DE MONITORING DEBEZIUM
-- ═══════════════════════════════════════════════════════════════════

-- Vérifier les slots de réplication actifs
SELECT 
    slot_name,
    plugin,
    slot_type,
    database,
    active,
    active_pid,
    restart_lsn,
    confirmed_flush_lsn
FROM pg_replication_slots
WHERE slot_name LIKE 'debezium%';

-- Vérifier l'activité de réplication
SELECT 
    pid,
    usename,
    application_name,
    client_addr,
    backend_start,
    state,
    sent_lsn,
    write_lsn,
    flush_lsn,
    replay_lsn,
    sync_state
FROM pg_stat_replication;

-- ═══════════════════════════════════════════════════════════════════
-- 🔍 TROUBLESHOOTING
-- ═══════════════════════════════════════════════════════════════════

-- Si aucun message n'arrive dans C#, vérifiez:

-- 1. Debezium connector status (Aiven Console):
--    https://console.aiven.io → ia-kafka-connect → Connectors
--    Status doit être: RUNNING

-- 2. Kafka topic existe et contient des messages:
--    https://console.aiven.io → ia-kafka-bus → Topics
--    Topic: pg_diagnostics.public.diagnostics
--    Cliquez "Fetch messages"

-- 3. Consumer group actif:
--    https://console.aiven.io → ia-kafka-bus → Consumer Groups
--    Cherchez: vmed327-consumer-group
--    Lag doit être: 0 (si tous les messages sont consommés)

-- 4. Logs PostgreSQL (si erreurs de réplication):
--    https://console.aiven.io → ia-postgres-db → Logs

-- ═══════════════════════════════════════════════════════════════════
-- ✅ RÉSULTAT ATTENDU
-- ═══════════════════════════════════════════════════════════════════

-- Dans la console C# (dotnet run), vous devriez voir:
--
-- [15:XX:XX INF] Message reçu (Offset X)
-- [15:XX:XX INF] 📬 Message Debezium reçu: Op=c, ID=3, Text=Test CDC #1 - Insertion simple...
-- [15:XX:XX INF] ✅ SANTÉ DU PROJET: Healthy | Mémoire: 80MB | ...
--
-- Si injection SQL détectée:
-- [15:XX:XX ERR] 🚨 TENTATIVE D'ATTAQUE DÉTECTÉE : Le diagnostic contient des caractères suspects...
--
-- Si tout fonctionne, le diagnostic sera:
-- 1. Inséré dans PostgreSQL ✅
-- 2. Capturé par Debezium ✅
-- 3. Publié sur Kafka ✅
-- 4. Consommé par C# ✅
-- 5. Validé par InputValidator ✅
-- 6. Envoyé à Gemini IA ✅
-- 7. Mise à jour dans PostgreSQL ✅

-- ═══════════════════════════════════════════════════════════════════
