-- ═══════════════════════════════════════════════════════════════════
-- DIAGNOSTIC COMPLET POSTGRESQL POUR DEBEZIUM
-- Exécutez ce script dans DBeaver pour diagnostiquer les problèmes
-- ═══════════════════════════════════════════════════════════════════

-- 1. Vérifier que la table existe et contient des données
SELECT '1. TABLE DIAGNOSTICS' AS etape, 
       COUNT(*) AS nb_lignes,
       CASE 
           WHEN COUNT(*) > 0 THEN '✅ Table a des données'
           ELSE '❌ Table vide - Debezium n''a rien à capturer'
       END AS status
FROM public.diagnostics;

-- Afficher les 3 dernières lignes
SELECT '   Dernières lignes:' AS info, * 
FROM public.diagnostics 
ORDER BY date_creation DESC 
LIMIT 3;

-- 2. Vérifier que la publication existe
SELECT '2. PUBLICATION' AS etape,
       pubname,
       CASE 
           WHEN pubname = 'dbz_publication' THEN '✅ Publication existe'
           ELSE '❌ Publication manquante'
       END AS status
FROM pg_publication 
WHERE pubname = 'dbz_publication';

-- 3. Vérifier que la table est dans la publication
SELECT '3. TABLE DANS PUBLICATION' AS etape,
       schemaname || '.' || tablename AS table_complete,
       CASE 
           WHEN tablename = 'diagnostics' THEN '✅ Table incluse dans publication'
           ELSE '⚠️ Problème de configuration'
       END AS status
FROM pg_publication_tables 
WHERE pubname = 'dbz_publication';

-- 4. Vérifier REPLICA IDENTITY
SELECT '4. REPLICA IDENTITY' AS etape,
       relname AS table_name,
       CASE relreplident
           WHEN 'f' THEN '✅ FULL (Correct pour Debezium)'
           WHEN 'd' THEN '⚠️ DEFAULT (fonctionne mais FULL est mieux)'
           WHEN 'n' THEN '❌ NOTHING (Debezium ne peut pas capturer)'
           ELSE '⚠️ ' || relreplident
       END AS status
FROM pg_class 
WHERE relname = 'diagnostics';

-- 5. Vérifier les slots de réplication
SELECT '5. REPLICATION SLOTS' AS etape,
       slot_name,
       plugin,
       active,
       CASE 
           WHEN active THEN '✅ Slot actif (Debezium connecté)'
           ELSE '⚠️ Slot inactif (Debezium pas connecté ou erreur)'
       END AS status
FROM pg_replication_slots
WHERE slot_name LIKE '%debezium%' OR slot_name LIKE '%slot%';

-- 6. Vérifier les permissions de l'utilisateur
SELECT '6. PERMISSIONS UTILISATEUR' AS etape,
       rolname AS user_name,
       rolreplication AS peut_repliquer,
       CASE 
           WHEN rolreplication THEN '✅ Permissions de réplication OK'
           ELSE '❌ Manque permissions de réplication'
       END AS status
FROM pg_roles 
WHERE rolname = 'avnadmin';

-- ═══════════════════════════════════════════════════════════════════
-- ACTIONS CORRECTIVES (si nécessaire)
-- ═══════════════════════════════════════════════════════════════════

-- SI la publication n'existe pas, exécutez :
-- DROP PUBLICATION IF EXISTS dbz_publication;
-- CREATE PUBLICATION dbz_publication FOR TABLE public.diagnostics;

-- SI REPLICA IDENTITY n'est pas FULL, exécutez :
-- ALTER TABLE public.diagnostics REPLICA IDENTITY FULL;

-- SI la table est vide, insérez des données de test :
-- INSERT INTO public.diagnostics (diagnostic_text, ia_guidance) 
-- VALUES ('Test Debezium CDC', 'Données de test pour vérifier CDC');

-- ═══════════════════════════════════════════════════════════════════
-- RÉSUMÉ ATTENDU POUR QUE DEBEZIUM FONCTIONNE
-- ═══════════════════════════════════════════════════════════════════
-- 1. Table 'diagnostics' : ✅ Existe avec des données
-- 2. Publication 'dbz_publication' : ✅ Existe
-- 3. Table dans publication : ✅ public.diagnostics incluse
-- 4. REPLICA IDENTITY : ✅ FULL
-- 5. Replication slot : ✅ Actif (si Debezium connecté)
-- 6. Permissions : ✅ avnadmin peut répliquer
-- ═══════════════════════════════════════════════════════════════════
