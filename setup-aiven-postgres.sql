/*
  ═══════════════════════════════════════════════════════════════════
  SCRIPT SQL FINAL POUR AIVEN POSTGRESQL
  ═══════════════════════════════════════════════════════════════════
  
  À EXÉCUTER DANS DBEAVER (connecté à ia-postgres-db)
  
  Ce script résout TOUTES les erreurs Debezium :
  - ✅ Crée la table `diagnostics` (résout l'erreur 42P01)
  - ✅ Configure REPLICA IDENTITY FULL (nécessaire pour CDC)
  - ✅ Crée la publication `dbz_publication` (résout ConnectException)
  
  INSTRUCTIONS :
  1. Ouvrez DBeaver
  2. Connectez-vous à votre service PostgreSQL Aiven (ia-postgres-db)
  3. Ouvrez un nouvel éditeur SQL (SQL Editor)
  4. Copiez-collez CE SCRIPT ENTIER
  5. Exécutez tout le script en une seule fois (Ctrl+Enter ou F5)
  6. Vérifiez les résultats dans la console DBeaver
  
  ═══════════════════════════════════════════════════════════════════
*/

-- ═══════════════════════════════════════════════════════════════════
-- 1. CRÉER LA TABLE DIAGNOSTICS (La fondation manquante)
-- ═══════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.diagnostics (
    id SERIAL PRIMARY KEY,
    diagnostic_text TEXT NOT NULL,
    ia_guidance TEXT,
    date_creation TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    
    -- Métadonnées utiles pour le tracking
    created_by VARCHAR(100) DEFAULT CURRENT_USER,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Ajouter un commentaire pour la documentation
COMMENT ON TABLE public.diagnostics IS 'Table de diagnostics médicaux avec guidance IA - Configurée pour Debezium CDC';
COMMENT ON COLUMN public.diagnostics.diagnostic_text IS 'Texte du diagnostic médical';
COMMENT ON COLUMN public.diagnostics.ia_guidance IS 'Recommandations générées par Gemini AI';
COMMENT ON COLUMN public.diagnostics.date_creation IS 'Date et heure de création du diagnostic';

-- ═══════════════════════════════════════════════════════════════════
-- 2. CONFIGURER LA TABLE POUR DEBEZIUM CDC
-- ═══════════════════════════════════════════════════════════════════

-- REPLICA IDENTITY FULL : Debezium capture TOUTES les colonnes (avant/après modification)
-- Ceci est OBLIGATOIRE pour que Debezium puisse capturer les changements complets
ALTER TABLE public.diagnostics REPLICA IDENTITY FULL;

-- Créer un index pour optimiser les requêtes par date
CREATE INDEX IF NOT EXISTS idx_diagnostics_date_creation 
    ON public.diagnostics (date_creation DESC);

-- ═══════════════════════════════════════════════════════════════════
-- 3. CRÉER LA PUBLICATION DEBEZIUM (Résout "autocreation is disabled")
-- ═══════════════════════════════════════════════════════════════════

-- Supprimer l'ancienne publication si elle existe (pour être sûr de repartir propre)
DROP PUBLICATION IF EXISTS dbz_publication;

-- Créer la publication pour la table diagnostics
-- Cette publication autorise Debezium à lire les changements sur cette table
CREATE PUBLICATION dbz_publication FOR TABLE public.diagnostics;

-- ═══════════════════════════════════════════════════════════════════
-- 4. VÉRIFICATIONS FINALES (Affiche les résultats pour confirmation)
-- ═══════════════════════════════════════════════════════════════════

-- Vérifier que la table existe
SELECT 
    schemaname AS schema,
    tablename AS table_name,
    tableowner AS owner
FROM pg_tables 
WHERE tablename = 'diagnostics';

-- Vérifier que la publication est créée
SELECT 
    pubname AS publication_name,
    puballtables AS publishes_all_tables,
    pubinsert AS publishes_insert,
    pubupdate AS publishes_update,
    pubdelete AS publishes_delete
FROM pg_publication 
WHERE pubname = 'dbz_publication';

-- Vérifier les tables incluses dans la publication
SELECT 
    schemaname AS schema,
    tablename AS table_name
FROM pg_publication_tables 
WHERE pubname = 'dbz_publication';

-- Vérifier REPLICA IDENTITY
SELECT 
    relname AS table_name,
    CASE relreplident
        WHEN 'd' THEN 'DEFAULT (clé primaire uniquement)'
        WHEN 'n' THEN 'NOTHING (pas de réplication)'
        WHEN 'f' THEN 'FULL (toutes les colonnes) ✅'
        WHEN 'i' THEN 'INDEX (via un index unique)'
    END AS replica_identity
FROM pg_class 
WHERE relname = 'diagnostics';

-- ═══════════════════════════════════════════════════════════════════
-- 5. DONNÉES DE TEST (Optionnel - Pour vérifier que tout fonctionne)
-- ═══════════════════════════════════════════════════════════════════

-- Insérer un diagnostic de test
INSERT INTO public.diagnostics (diagnostic_text, ia_guidance) 
VALUES 
    ('Patient présente des symptômes de grippe saisonnière', 
     'Repos, hydratation, paracétamol si fièvre. Consulter si aggravation.');

-- Afficher le test
SELECT * FROM public.diagnostics ORDER BY date_creation DESC LIMIT 1;

-- ═══════════════════════════════════════════════════════════════════
-- ✅ SCRIPT TERMINÉ
-- ═══════════════════════════════════════════════════════════════════
-- 
-- RÉSULTATS ATTENDUS :
-- 1. Table "diagnostics" créée avec 1 ligne de test
-- 2. Publication "dbz_publication" active
-- 3. REPLICA IDENTITY = FULL
-- 
-- PROCHAINE ÉTAPE :
-- Configurez votre connecteur Debezium dans Aiven Console
-- (Utilisez le fichier debezium-aiven-connector-config.json)
-- 
-- ═══════════════════════════════════════════════════════════════════
