# 🚀 Guide de Configuration Aiven Cloud (SANS Docker)

## ⚠️ IMPORTANT : Ce guide est pour votre Dell Vostro 2009
**Votre PC ne peut PAS exécuter Docker/WSL2.** Ce guide utilise **uniquement Aiven Cloud**.

---

## 📋 Prérequis

✅ Compte Aiven Cloud actif  
✅ Service PostgreSQL Aiven : `ia-postgres-db-yveslandry363-974a.g.aivencloud.com:15593`  
✅ Service Kafka Aiven configuré avec mTLS  
✅ Service Kafka Connect Aiven : `ia-kafka-connect`  
✅ DBeaver installé sur votre PC  
✅ Certificats Kafka dans `kafka_certs/` (ca.pem, service.cert, service.key)  

---

## 🎯 Étape 1 : Configuration PostgreSQL (DBeaver)

### 1.1 Ouvrir DBeaver et se connecter

1. Lancez **DBeaver**
2. Connectez-vous à votre service PostgreSQL Aiven :
   - **Host** : `ia-postgres-db-yveslandry363-974a.g.aivencloud.com`
   - **Port** : `15593`
   - **Database** : `defaultdb`
   - **Username** : `avnadmin`
   - **Password** : (votre mot de passe Aiven)
   - **SSL Mode** : `Require`

### 1.2 Exécuter le script SQL de configuration

1. Clic droit sur la connexion → **SQL Editor** → **New SQL Script**
2. Ouvrez le fichier `setup-aiven-postgres.sql` dans ce projet
3. **Copiez TOUT le contenu** du fichier
4. **Collez** dans l'éditeur SQL de DBeaver
5. **Exécutez le script entier** (Ctrl+Enter ou bouton ▶️)

### 1.3 Vérifier les résultats

Vous devriez voir dans la console DBeaver :

```
✅ Table "diagnostics" créée
✅ Publication "dbz_publication" créée
✅ REPLICA IDENTITY = FULL
✅ 1 ligne de test insérée
```

**Requêtes de vérification** (exécutez-les une par une) :

```sql
-- Vérifier la table
SELECT * FROM public.diagnostics;

-- Vérifier la publication
SELECT * FROM pg_publication WHERE pubname = 'dbz_publication';

-- Vérifier REPLICA IDENTITY
SELECT relname, relreplident FROM pg_class WHERE relname = 'diagnostics';
-- Doit afficher : relreplident = 'f' (FULL)
```

---

## 🔌 Étape 2 : Configuration Debezium dans Aiven Console

### 2.1 Accéder au service Kafka Connect

1. Allez sur **https://console.aiven.io**
2. Connectez-vous à votre compte
3. Sélectionnez votre projet
4. Cliquez sur le service **`ia-kafka-connect`**

### 2.2 Configurer le connecteur Debezium

#### Si le connecteur existe déjà (en statut FAILED)

1. Allez dans l'onglet **Connectors**
2. Trouvez `debezium-pg-source-diagnostics`
3. Cliquez sur le connecteur → **Edit configuration**
4. **Supprimez tout le JSON** existant
5. Ouvrez le fichier `debezium-aiven-connector-config.json` de ce projet
6. **Copiez tout le contenu**
7. **Remplacez les 3 valeurs** :
   - `"database.hostname"` → votre hostname PostgreSQL Aiven
   - `"database.port"` → votre port PostgreSQL (15593)
   - `"database.password"` → votre mot de passe PostgreSQL
8. **Collez** dans Aiven Console
9. Cliquez sur **Save configuration**

#### Si le connecteur n'existe pas

1. Allez dans l'onglet **Connectors**
2. Cliquez sur **Create connector**
3. Sélectionnez **Debezium PostgreSQL Source**
4. Ouvrez le fichier `debezium-aiven-connector-config.json` de ce projet
5. **Remplacez les 3 valeurs** (hostname, port, password)
6. **Collez la configuration** dans l'éditeur Aiven
7. Cliquez sur **Create connector**

### 2.3 Vérifier le statut du connecteur

Après sauvegarde, attendez **15-30 secondes**, puis :

1. Rafraîchissez la page
2. Le connecteur devrait afficher :
   - **État** : ✅ `RUNNING` (coche verte)
   - **Tasks** : `1/1 running`

**Si le connecteur est en état FAILED** :

1. Cliquez sur le connecteur
2. Allez dans l'onglet **Logs**
3. Cherchez l'erreur exacte
4. **Erreurs courantes** :
   - `"relation "public.diagnostics" does not exist"` → Retournez à l'Étape 1.2
   - `"publication "dbz_publication" does not exist"` → Retournez à l'Étape 1.2
   - `"authentication failed"` → Vérifiez le mot de passe dans la config
   - `"must be superuser to create publication"` → Utilisez `avnadmin` (role admin Aiven)

---

## 🎉 Étape 3 : Test Final

### 3.1 Vérifier le topic Kafka

1. Dans Aiven Console, allez sur votre service **Kafka**
2. Allez dans l'onglet **Topics**
3. Vous devriez voir le topic : **`pg_diagnostics.public.diagnostics`**
4. Cliquez dessus → **Messages**
5. Vous devriez voir **1 message** (la ligne de test insérée à l'Étape 1.2)

### 3.2 Lancer l'application C#

```powershell
# Dans le terminal PowerShell
cd "D:\VMed327\Prototype Gemini"

# Option 1 : Lancer avec le script automatique
.\run_ia_ultimate.ps1

# Option 2 : Lancer manuellement
dotnet build
dotnet run
```

**Sortie attendue** :

```
info: Microsoft.Hosting.Lifetime[14]
      Now listening on: http://localhost:5000
info: Microsoft.Hosting.Lifetime[0]
      Application started. Press Ctrl+C to shut down.

🔍 Kafka Consumer démarré - Topic: pg_diagnostics.public.diagnostics
✅ Message consommé: {"diagnostic_text":"Patient présente...","ia_guidance":"Repos, hydratation..."}
```

### 3.3 Test de bout en bout

**Dans DBeaver** (pendant que l'application C# tourne) :

```sql
-- Insérer un nouveau diagnostic
INSERT INTO public.diagnostics (diagnostic_text, ia_guidance) 
VALUES (
    'Patient avec toux sèche persistante depuis 5 jours',
    'Consulter médecin. Possibilité de bronchite. Eviter automédication.'
);
```

**Dans le terminal C#**, vous devriez voir **IMMÉDIATEMENT** :

```
✅ Message Kafka reçu depuis PostgreSQL:
   Diagnostic: Patient avec toux sèche persistante depuis 5 jours
   Guidance: Consulter médecin. Possibilité de bronchite...
   Date: 2025-11-06T02:45:30Z
```

---

## 🐛 Troubleshooting

### ❌ Erreur : "Publication autocreation is disabled"

**Cause** : La publication PostgreSQL n'existe pas  
**Solution** : Retournez à l'**Étape 1.2** et exécutez `setup-aiven-postgres.sql`

### ❌ Erreur : "relation "public.diagnostics" does not exist"

**Cause** : La table n'a pas été créée  
**Solution** : Retournez à l'**Étape 1.2** et exécutez `setup-aiven-postgres.sql`

### ❌ Connecteur en statut FAILED

1. Allez dans **Aiven Console** → Connecteur → **Logs**
2. Copiez l'erreur exacte
3. Vérifiez :
   - Credentials PostgreSQL corrects (`database.password`)
   - Publication créée (`SELECT * FROM pg_publication`)
   - Table créée (`SELECT * FROM public.diagnostics`)

### ❌ Application C# : "No brokers available"

**Cause** : Certificats Kafka SSL incorrects  
**Solution** :

1. Vérifiez que les certificats existent :
   ```powershell
   ls kafka_certs\
   # Doit afficher : ca.pem, service.cert, service.key
   ```

2. Téléchargez les certificats depuis Aiven Console :
   - Service Kafka → **Overview** → **Access Key**, **Access Certificate**, **CA Certificate**
   - Sauvegardez dans `kafka_certs/`

### ❌ Application C# : "Authentication failed"

**Cause** : Chemin des certificats incorrect  
**Solution** : Vérifiez `appsettings.json` :

```json
"Kafka": {
  "BootstrapServers": "votre-kafka-aiven.aivencloud.com:15591",
  "SslCaLocation": "D:\\VMed327\\Prototype Gemini\\kafka_certs\\ca.pem",
  "SslCertificateLocation": "D:\\VMed327\\Prototype Gemini\\kafka_certs\\service.cert",
  "SslKeyLocation": "D:\\VMed327\\Prototype Gemini\\kafka_certs\\service.key"
}
```

---

## ✅ Checklist de Validation Finale

Avant de considérer le projet terminé, vérifiez :

- [ ] DBeaver connecté à PostgreSQL Aiven sans erreur
- [ ] Table `public.diagnostics` existe avec REPLICA IDENTITY FULL
- [ ] Publication `dbz_publication` créée
- [ ] Connecteur Debezium en état **RUNNING** dans Aiven Console
- [ ] Topic Kafka `pg_diagnostics.public.diagnostics` contient au moins 1 message
- [ ] Application C# démarre sans erreur
- [ ] Application C# affiche "Kafka Consumer démarré"
- [ ] INSERT dans PostgreSQL → Message visible dans le terminal C# (< 2 secondes)

---

## 🎯 Architecture Finale (SANS Docker)

```
┌─────────────────────────────────────────────────────────────┐
│                    AIVEN CLOUD                               │
│                                                              │
│  ┌─────────────────┐                                         │
│  │  PostgreSQL DB  │ (ia-postgres-db)                       │
│  │  Port: 15593    │                                         │
│  │  Table: diagnostics                                      │
│  │  Publication: dbz_publication                            │
│  └────────┬────────┘                                         │
│           │ CDC (Change Data Capture)                        │
│           ▼                                                  │
│  ┌─────────────────┐                                         │
│  │ Kafka Connect   │ (ia-kafka-connect)                     │
│  │ Debezium        │                                         │
│  └────────┬────────┘                                         │
│           │ Publishes changes                                │
│           ▼                                                  │
│  ┌─────────────────┐                                         │
│  │  Kafka Broker   │ (ia-kafka)                             │
│  │  Port: 15591    │                                         │
│  │  Topic: pg_diagnostics.public.diagnostics                │
│  └────────┬────────┘                                         │
└───────────┼─────────────────────────────────────────────────┘
            │ mTLS (SSL Certificates)
            ▼
   ┌────────────────────┐
   │  VOTRE PC          │ (Dell Vostro 2009)
   │  Application C#    │
   │  .NET 9            │
   │  Kafka Consumer    │
   │  Gemini AI Client  │
   └────────────────────┘
```

**Aucun Docker requis sur votre PC!** ✅

---

## 📚 Fichiers Importants

- `setup-aiven-postgres.sql` → Script SQL pour DBeaver
- `debezium-aiven-connector-config.json` → Configuration Debezium pour Aiven Console
- `appsettings.json` → Configuration application C# (Kafka, PostgreSQL, Gemini)
- `Program.cs` → Point d'entrée de l'application
- `Services/KafkaConsumerService.cs` → Consommateur Kafka
- `GeminiApiService.cs` → Client Gemini AI

---

## 🚀 Commandes Rapides

```powershell
# Build et lancement
dotnet build && dotnet run

# Vérifier les certificats Kafka
ls kafka_certs\

# Tester la connexion PostgreSQL depuis C#
dotnet run --launch-profile "PostgreSQL-Test"

# Logs détaillés
$env:ASPNETCORE_ENVIRONMENT="Development"; dotnet run
```

---

**Bonne chance! 🎉 Vous êtes à 2 minutes de la victoire!**
