-- Vérification rapide avant configuration Aiven
-- Exécutez ce SQL dans DBeaver pour confirmer que tout est OK

-- 1. Vérifier que la table existe
SELECT 'Table diagnostics:' AS verification, 
       COUNT(*) AS nb_lignes 
FROM public.diagnostics;

-- 2. Vérifier que la publication existe
SELECT 'Publication:' AS verification, 
       pubname, 
       CASE WHEN pubname IS NOT NULL THEN '✅ Créée' ELSE '❌ Manquante' END AS status
FROM pg_publication 
WHERE pubname = 'dbz_publication';

-- 3. Vérifier REPLICA IDENTITY
SELECT 'REPLICA IDENTITY:' AS verification,
       CASE relreplident
           WHEN 'f' THEN '✅ FULL (Correct pour Debezium)'
           ELSE '❌ ' || relreplident || ' (Devrait être FULL)'
       END AS status
FROM pg_class 
WHERE relname = 'diagnostics';

-- Si la publication n'existe pas, exécutez ceci:
-- DROP PUBLICATION IF EXISTS dbz_publication;
-- CREATE PUBLICATION dbz_publication FOR TABLE public.diagnostics;
