# 🚀 Automatisation Complète - Prototype Gemini

## Vue d'ensemble

Ce projet contient un système d'automatisation complète qui :
- ✅ Compile le projet
- ✅ Démarre l'application automatiquement  
- ✅ Insère des données de test CDC dans PostgreSQL
- ✅ Consomme les événements Kafka/Debezium
- ✅ Appelle Vertex AI avec découverte automatique du meilleur modèle Gemini

## 📋 Prérequis

1. **.NET 9.0 SDK** installé
2. **PostgreSQL** (Aiven ou local) configuré avec Debezium
3. **Kafka** (Aiven ou local) avec le topic `pg_diagnostics.public.diagnostics`
4. **gcp-key.json** dans le répertoire racine (pour OAuth2 Vertex AI)
5. **appsettings.json** configuré avec vos credentials

## 🎯 Utilisation Rapide

### Option 1 : Script tout-en-un (RECOMMANDÉ)

```powershell
# Lancer avec valeurs par défaut (5 insertions)
.\auto-run.ps1

# Lancer avec nombre d'insertions personnalisé
.\auto-run.ps1 -TestInserts 10
```

**Ce script fait TOUT automatiquement :**
1. Build du projet en mode Release
2. Nettoyage des processus existants
3. Démarrage de l'application en arrière-plan
4. Attend 35 secondes que l'app soit prête
5. Insère N diagnostics dans PostgreSQL (intervalle : 8 sec)
6. Affiche les logs en temps réel
7. Reste actif - appuyez sur Entrée pour arrêter

### Option 2 : Script avec plus d'options

```powershell
# Lancer sans rebuild
.\run-automated.ps1 -SkipBuild

# Personnaliser le nombre d'insertions et l'intervalle
.\run-automated.ps1 -InsertCount 10 -InsertInterval 5
```

### Option 3 : Insertion manuelle rapide

```powershell
# Insère un diagnostic dans PostgreSQL
.\quick-insert.ps1
```

## 📊 Que se passe-t-il ?

### 1. Compilation
```
[1/4] Build...
  Restauration terminée (4,4s)
  Prototype Gemini a réussi (1,9s)
Build OK
```

### 2. Démarrage de l'application

L'application :
- Se connecte à **Kafka** (Aiven)
- Se connecte à **PostgreSQL** (Aiven)  
- S'abonne au topic Debezium
- Active le **health monitor**
- Attend les messages CDC

### 3. Insertions CDC automatiques

Le script insère des diagnostics variés :
```
[4/4] Insertions CDC automatiques (5)...
  [1/5] ID=123 | Patient avec fievre elevee (39C) et toux depuis 3 jours...
           Attente 8 sec...
  [2/5] ID=124 | Douleurs abdominales aigues, quadrant inferieur droit...
```

### 4. Traitement automatique

**Pour chaque insertion :**

1. **Debezium** capture le changement dans PostgreSQL
2. **Kafka** reçoit l'événement CDC
3. **L'application** consomme le message
4. **Gemini Service** :
   - Authentifie avec OAuth2 (gcp-key.json)
   - Découvre le meilleur modèle Gemini disponible
   - Préférence : `gemini-2.5-pro` → `gemini-2.0-pro` → `gemini-1.5-pro` → ...
   - Cache le modèle sélectionné (30 min)
   - Appelle Vertex AI avec le diagnostic
5. **Réponse IA** traitée et loggée

## 🔍 Logs en temps réel

Les logs montrent :
```
[17:24:02 INF] 📬 Message Debezium reçu: ID=10, Text=Patient with severe headache...
[17:24:02 INF] [GEMINI_AUTH] Utilisation de OAuth2 avec Service Account
[17:24:03 INF] [VICTORY_API] Réponse de gemini-1.5-pro reçue en 1234ms
```

### Logs de découverte de modèle

Si le listing des modèles échoue :
```
[GEMINI_DISCOVERY_WARN] Echec list models (NotFound): ...
```

Le système tente alors de prober chaque modèle individuellement.

### Logs de succès

```
[VICTORY_API] Réponse de {Model} reçue en {TimeMs}ms
```
Indique qu'un modèle Gemini a répondu avec succès.

## 🛠️ Configuration

### Modèles Gemini prioritaires

Voir `Services/GeminiApiService.cs` ligne ~165 :
```csharp
var preferred = new[]
{
    "gemini-2.5-pro",
    "gemini-2.0-pro",
    "gemini-1.5-pro-002",
    "gemini-1.5-pro",
    "gemini-1.5-flash-002",
    "gemini-1.5-flash"
};
```

### Personnaliser les messages de test

Éditer `auto-run.ps1` ligne ~80 :
```powershell
$diagnostics = @(
    "Patient avec fievre elevee (39C) et toux depuis 3 jours",
    "Douleurs abdominales aigues, quadrant inferieur droit",
    # Ajoutez vos propres messages ici
)
```

## ⚙️ Paramètres

### auto-run.ps1

| Paramètre | Type | Défaut | Description |
|-----------|------|--------|-------------|
| `TestInserts` | int | 3 | Nombre d'insertions automatiques |

### run-automated.ps1

| Paramètre | Type | Défaut | Description |
|-----------|------|--------|-------------|
| `SkipBuild` | switch | false | Ignorer la compilation |
| `InsertCount` | int | 5 | Nombre d'insertions |
| `InsertInterval` | int | 10 | Intervalle en secondes entre insertions |

## 📝 Fichiers du projet

```
Prototype Gemini/
├── auto-run.ps1                    ← Script automatisation simplifié (PRINCIPAL)
├── run-automated.ps1               ← Script avec options avancées
├── quick-insert.ps1                ← Insertion manuelle rapide
├── launch-full-automation.ps1      ← Script complet avec interface
│
├── Services/
│   ├── GeminiApiService.cs         ← Découverte et appels Vertex AI
│   └── KafkaConsumerService.cs     ← Consumer Debezium
│
├── appsettings.json                ← Configuration (Kafka, Postgres, GCP)
├── gcp-key.json                    ← Credentials service account GCP
│
└── kafka_certs/                    ← Certificats SSL Kafka
    ├── ca.pem
    ├── service.cert
    └── service.key
```

## 🔧 Dépannage

### L'application se ferme immédiatement

**Cause** : Erreur de configuration ou credentials invalides

**Solution** :
1. Vérifiez `appsettings.json`
2. Vérifiez que `gcp-key.json` existe
3. Testez la connexion Postgres :
   ```powershell
   psql -h HOST -p PORT -U USER -d DATABASE
   ```

### Erreur "Model NOT_FOUND"

**Cause** : Le modèle n'existe pas dans votre région ou projet

**Solutions** :
1. Vérifiez que Vertex AI est activé :
   ```bash
   gcloud services enable aiplatform.googleapis.com
   ```

2. Vérifiez les permissions IAM :
   ```bash
   gcloud projects add-iam-policy-binding PROJECT_ID \
     --member="serviceAccount:EMAIL@PROJECT.iam.gserviceaccount.com" \
     --role="roles/aiplatform.user"
   ```

3. Testez manuellement les modèles disponibles :
   ```bash
   gcloud ai models list --region=europe-west4
   ```

### Kafka connection errors

**Symptôme** : `1/1 brokers are down`

**C'est normal** : Messages transitoires au démarrage. Si persistant :
1. Vérifiez les certificats dans `kafka_certs/`
2. Vérifiez l'URL Kafka dans `appsettings.json`
3. Testez avec `kafkacat` :
   ```bash
   kafkacat -b BROKER:PORT -L \
     -X security.protocol=SSL \
     -X ssl.ca.location=kafka_certs/ca.pem
   ```

### Erreur Npgsql.dll

**Cause** : Build pas exécuté ou DLL manquante

**Solution** :
```powershell
dotnet restore
dotnet build -c Release
```

## 📈 Performance

### Métriques typiques

- **Démarrage app** : ~30 secondes
- **Insertion CDC** : ~50-200ms (Postgres → Kafka)
- **Consommation Kafka** : <100ms
- **Appel Vertex AI** : 500-2000ms (selon modèle)
- **Traitement total** : ~1-3 secondes par diagnostic

### Monitoring

L'application expose :
- **Health checks** (toutes les 10 secondes)
- **Métriques OpenTelemetry** (endpoint configuré)
- **Logs Serilog** (console + fichier JSON compact)

## 🎓 Exemples d'utilisation

### Scénario 1 : Test rapide

```powershell
# Build, démarre, insère 3 diagnostics, affiche les logs
.\auto-run.ps1

# Appuyez sur Entrée quand terminé
```

### Scénario 2 : Stress test

```powershell
# 20 insertions avec intervalle de 3 secondes
.\run-automated.ps1 -InsertCount 20 -InsertInterval 3
```

### Scénario 3 : Développement

```powershell
# Skip build si déjà compilé
.\run-automated.ps1 -SkipBuild -InsertCount 5
```

### Scénario 4 : Production-like

```powershell
# Démarrer l'app sans insertions auto
.\run-automated.ps1 -InsertCount 0

# Dans un autre terminal, insérer manuellement
while ($true) {
    .\quick-insert.ps1
    Start-Sleep -Seconds 30
}
```

## 🚦 Statut de santé

L'application affiche son état :
```
✅ SANTÉ DU PROJET: Healthy | Mémoire: 95MB | Threads: 36 | Uptime: 00:05:23
```

États possibles :
- **Healthy** : Tout fonctionne
- **Degraded** : Problèmes de performance (CPU élevé, etc.)
- **Unhealthy** : Composants critiques défaillants

## 📚 Ressources

- [Documentation Vertex AI](https://cloud.google.com/vertex-ai/docs)
- [Debezium PostgreSQL Connector](https://debezium.io/documentation/reference/connectors/postgresql.html)
- [Confluent Kafka .NET](https://docs.confluent.io/kafka-clients/dotnet/current/overview.html)

## 🤝 Support

En cas de problème :
1. Consultez les logs : `logs/prototype-*.log`
2. Vérifiez les connexions : Kafka, Postgres, Vertex AI
3. Testez les credentials : gcp-key.json, appsettings.json
4. Vérifiez les permissions IAM dans GCP

## 🎉 Succès

Si vous voyez :
```
[VICTORY_API] Réponse de gemini-2.5-pro reçue en 1234ms
```

**Félicitations !** Votre pipeline fonctionne end-to-end :
- PostgreSQL → Debezium → Kafka → App → Vertex AI ✅
