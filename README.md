# Prototype Gemini

## ⚠️ IMPORTANT : Utilisez Aiven Cloud (Pas de Docker local)

**Votre PC Dell Vostro 2009 ne peut pas exécuter Docker/WSL2.**

👉 **Suivez le guide complet** : [README-AIVEN.md](README-AIVEN.md)

Ce guide contient :
- ✅ Configuration PostgreSQL Aiven (script SQL pour DBeaver)
- ✅ Configuration Debezium dans Aiven Console (pas de Docker)
- ✅ Tests de bout en bout
- ✅ Troubleshooting complet

---

## État du projet
- **Framework cible** : .NET 9
- **Dépendances** : dernières versions stables (Npgsql 9.0.4, OpenTelemetry 1.13.1, etc.)
- **Infrastructure** : Aiven Cloud (PostgreSQL + Kafka + Kafka Connect)
- **CI/CD** : GitHub Actions compile, restaure et audite les vulnérabilités à chaque push/PR et chaque jour
- **Mise à jour auto** : Dependabot surveille et propose les mises à jour NuGet

## � Démarrage Rapide (Aiven Cloud)

### 1. Configuration PostgreSQL (DBeaver)
```sql
-- Exécutez le fichier setup-aiven-postgres.sql dans DBeaver
-- Cela crée la table, la publication et configure CDC
```

### 2. Configuration Debezium (Aiven Console)
```
1. Allez sur console.aiven.io
2. Service ia-kafka-connect → Connectors
3. Éditez debezium-pg-source-diagnostics
4. Collez le contenu de debezium-aiven-connector-config.json
5. Remplacez le mot de passe PostgreSQL
6. Sauvegardez
```

### 3. Lancer l'application C#
```powershell
dotnet build
dotnet run
```

---

## �📊 Configuration Debezium CDC (Pour Docker - NON UTILISÉ)

### Prérequis
1. **PostgreSQL** avec accès administrateur (pour créer publications et slots de réplication)
2. **Kafka Connect** démarré et accessible
3. **Kafka** fonctionnel avec les topics créés

### Étape 1 : Configuration PostgreSQL

Exécutez le script PowerShell pour configurer PostgreSQL :

```powershell
.\setup-debezium-postgres.ps1
```

Ce script va automatiquement :
- ✅ Créer la publication `dbz_publication` pour la table `public.diagnostics`
- ✅ Activer le rôle de réplication pour l'utilisateur `avnadmin`
- ✅ Créer le slot de réplication logique `debezium_slot`
- ✅ Créer la table `diagnostics` si elle n'existe pas
- ✅ Vérifier les permissions et la configuration

**Alternative manuelle** : Si vous n'avez pas PowerShell, connectez-vous à PostgreSQL et exécutez :

```sql
-- Créer la publication
CREATE PUBLICATION dbz_publication FOR TABLE public.diagnostics;

-- Activer la réplication
ALTER ROLE avnadmin WITH REPLICATION;

-- Créer le slot de réplication
SELECT pg_create_logical_replication_slot('debezium_slot', 'pgoutput');

-- Vérifier
SELECT * FROM pg_publication;
SELECT * FROM pg_replication_slots;
```

### Étape 2 : Déploiement du connecteur Debezium

Déployez le connecteur via le script PowerShell :

```powershell
.\deploy-debezium-connector.ps1
```

**Options** :
```powershell
# Spécifier l'URL Kafka Connect (par défaut: http://localhost:8083)
.\deploy-debezium-connector.ps1 -KafkaConnectUrl "http://kafka-connect:8083"

# Spécifier un nom personnalisé
.\deploy-debezium-connector.ps1 -ConnectorName "mon-connecteur-postgres"
```

**Alternative manuelle** : Déployez via curl :

```bash
curl -X POST http://localhost:8083/connectors \
  -H "Content-Type: application/json" \
  -d @debezium-connector-config.json
```

### Étape 3 : Vérification

#### Vérifier le statut du connecteur

```powershell
curl http://localhost:8083/connectors/postgres-diagnostics-connector/status
```

Vous devriez voir :
```json
{
  "name": "postgres-diagnostics-connector",
  "connector": {
    "state": "RUNNING",
    "worker_id": "kafka-connect:8083"
  },
  "tasks": [
    {
      "id": 0,
      "state": "RUNNING",
      "worker_id": "kafka-connect:8083"
    }
  ]
}
```

#### Vérifier les messages Kafka

Consommez les messages du topic Debezium :

```bash
kafka-console-consumer --bootstrap-server localhost:9092 \
  --topic pg_diagnostics.public.diagnostics \
  --from-beginning
```

### 🔧 Troubleshooting

#### Erreur : "Publication autocreation is disabled"
➡️ **Solution** : Exécutez `setup-debezium-postgres.ps1` pour créer manuellement la publication

#### Erreur : "replication slot already exists"
➡️ **Solution** : Le slot existe déjà, vous pouvez continuer ou le supprimer :
```sql
SELECT pg_drop_replication_slot('debezium_slot');
```

#### Connecteur en état FAILED
➡️ **Solution** : Consultez les logs Kafka Connect :
```bash
docker logs kafka-connect
# ou
tail -f logs/connect.log
```

Vérifiez aussi les credentials PostgreSQL dans `debezium-connector-config.json`

#### Aucun message dans le topic Kafka
➡️ **Solutions** :
1. Vérifiez que la table `diagnostics` a des données
2. Vérifiez que le connecteur est en état RUNNING
3. Effectuez une modification dans la table pour déclencher CDC :
   ```sql
   INSERT INTO public.diagnostics (message, timestamp) VALUES ('test', NOW());
   ```

#### Topic Kafka non créé automatiquement
➡️ **Solution** : Créez manuellement le topic :
```bash
kafka-topics --create --bootstrap-server localhost:9092 \
  --topic pg_diagnostics.public.diagnostics \
  --partitions 3 \
  --replication-factor 1
```

### 📋 Commandes utiles

```powershell
# Lister tous les connecteurs
curl http://localhost:8083/connectors

# Obtenir la configuration d'un connecteur
curl http://localhost:8083/connectors/postgres-diagnostics-connector/config

# Redémarrer un connecteur
curl -X POST http://localhost:8083/connectors/postgres-diagnostics-connector/restart

# Supprimer un connecteur
curl -X DELETE http://localhost:8083/connectors/postgres-diagnostics-connector

# Mettre en pause un connecteur
curl -X PUT http://localhost:8083/connectors/postgres-diagnostics-connector/pause

# Reprendre un connecteur
curl -X PUT http://localhost:8083/connectors/postgres-diagnostics-connector/resume
```

## Points de vigilance
- **PostgreSQL DNS** : Le hostname Aiven configuré n'existe pas (vérifier les credentials et la connexion réseau)
- **OpenTelemetry** : Endpoint `localhost:4317` désactivé (démarrer un collector OTLP si vous voulez collecter les métriques/traces)
- **GoogleCredential** : usage corrigé, passage à ServiceAccountCredential pour la sécurité
- **Avertissements build** : surveiller les logs CI pour toute nouvelle vulnérabilité ou dépréciation
- **Debezium CDC** : Nécessite PostgreSQL avec permissions de réplication et Kafka Connect démarré

## Conseils maintenance
- Accepter les PR Dependabot pour rester à jour
- Surveiller les advisories NuGet et GitHub
- Tester les endpoints et la connexion DB après chaque mise à jour majeure

## Lancer le projet
```powershell
dotnet restore
dotnet build
dotnet run
```

## CI/CD
- Voir `.github/workflows/ci.yml` pour la configuration automatisé

