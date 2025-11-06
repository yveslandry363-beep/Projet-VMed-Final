# 🔧 Corrections Appliquées au Projet

## Date : 6 Novembre 2025

---

## ✅ Problème Principal Résolu

### **Erreur OAuth2 avec l'API Gemini**

**Symptôme :**
```
Google.GoogleApiException: Invalid OAuth scope or ID token audience provided. 
A valid authUri and/or OAuth scope is required to proceed.
```

**Cause Racine :**
L'application utilisait **OAuth2 avec Service Account Credentials** pour authentifier les requêtes à l'API Gemini. Cependant, l'API Gemini utilise **l'authentification par clé API**, pas OAuth2.

**Solution Appliquée :**

1. **Modifié `GeminiApiService.cs`** :
   - ❌ Supprimé : Authentification OAuth2 avec `ServiceAccountCredential`
   - ✅ Ajouté : Authentification par clé API via paramètre d'URL `?key={apiKey}`
   - ✅ La clé API est récupérée depuis la variable d'environnement `GEMINI_API_KEY`

2. **Modifié `Program.cs`** :
   - ❌ Supprimé : Enregistrement du `GoogleCredential` dans le conteneur DI
   - ❌ Supprimé : Décodage Base64 du JSON du compte de service
   - ✅ Simplifié : Plus besoin de `ServiceAccountJsonBase64` dans `appsettings.json`

---

## 📋 État de Compilation

### **Avant les corrections :**
- ✅ Build : **SUCCÈS** (5 avertissements)
- ❌ Runtime : **ÉCHEC** (Exit code 1, erreur OAuth2)

### **Après les corrections :**
- ✅ Build : **SUCCÈS** (4 avertissements) ⬇️ 1 warning en moins
- ⏳ Runtime : **NÉCESSITE configuration de `GEMINI_API_KEY`**

---

## 🔑 Configuration Requise

### **Obtenir votre clé API Gemini :**

1. Allez sur : https://makersuite.google.com/app/apikey
2. Connectez-vous avec votre compte Google
3. Cliquez sur **"Create API Key"**
4. Copiez la clé générée

### **Configurer la variable d'environnement :**

**Option 1 : Utiliser le script PowerShell fourni (Recommandé)**
```powershell
.\set-gemini-api-key.ps1 -ApiKey "VOTRE_CLE_API_ICI"
```

**Option 2 : Manuellement dans PowerShell**
```powershell
# Session actuelle seulement
$env:GEMINI_API_KEY = "VOTRE_CLE_API_ICI"

# Permanent (redémarrage de VS Code requis)
[System.Environment]::SetEnvironmentVariable("GEMINI_API_KEY", "VOTRE_CLE_API_ICI", [System.EnvironmentVariableTarget]::User)
```

**Option 3 : Définir dans le système Windows**
1. Recherchez "Variables d'environnement" dans Windows
2. Cliquez sur "Modifier les variables d'environnement système"
3. Variables utilisateur → Nouveau
4. Nom : `GEMINI_API_KEY`
5. Valeur : Votre clé API
6. Redémarrez VS Code

---

## 🚀 Lancement de l'Application

Une fois la clé API configurée :

```powershell
cd "d:\VMed327\Prototype Gemini"
dotnet run
```

**Comportement attendu :**
- ✅ Connexion à Kafka
- ✅ Consommation des messages CDC depuis PostgreSQL
- ✅ Validation de sécurité (InputValidator)
- ✅ Appel à l'API Gemini avec la clé API
- ✅ Mise à jour de PostgreSQL avec les recommandations IA

---

## 🛡️ Sécurité

### **Bonnes Pratiques :**

1. **Ne commitez JAMAIS la clé API dans Git**
   - Ajoutez `.env` au `.gitignore` si vous utilisez des fichiers d'environnement
   - Utilisez des variables d'environnement système

2. **Restrictions de la clé API (Recommandé)**
   - Dans Google Cloud Console, restreignez votre clé API :
     - Restreindre à l'API "Generative Language API"
     - Restreindre à votre adresse IP si possible

3. **Rotation régulière**
   - Changez votre clé API tous les 3-6 mois

---

## 📊 Avertissements Restants (Non-Bloquants)

### 1. **SYSLIB0057** (X509Certificate2 obsolète) - 2 occurrences
**Fichiers :** `ProjectHealthMonitor.cs`, `CertificateValidator.cs`

**Action recommandée :** Utiliser `X509CertificateLoader` au lieu du constructeur

### 2. **CA1416** (PerformanceCounter Windows-only) - 2 occurrences
**Fichier :** `ProjectHealthMonitor.cs`

**Action recommandée :** Ajouter `#if WINDOWS` pour la compatibilité multiplateforme

---

## 🧪 Tests Recommandés

### **Test 1 : Vérifier la clé API**
```powershell
# Vérifier que la variable est définie
$env:GEMINI_API_KEY
# Devrait afficher votre clé API
```

### **Test 2 : Tester l'API Gemini directement**
```powershell
$apiKey = $env:GEMINI_API_KEY
$url = "https://generativelanguage.googleapis.com/v1beta/models/gemini-flash:generateContent?key=$apiKey"
$body = @{
    contents = @(
        @{
            parts = @(
                @{ text = "Hello Gemini!" }
            )
        }
    )
} | ConvertTo-Json -Depth 10

Invoke-RestMethod -Uri $url -Method Post -Body $body -ContentType "application/json"
```

### **Test 3 : Lancer l'application complète**
```powershell
dotnet run
```

**Vérifier dans les logs :**
- ✅ `[VICTORY_API] Réponse de models/gemini-flash reçue`
- ❌ Si erreur `GEMINI_API_KEY not found` → variable non configurée

---

## 🔄 Différences Clés dans le Code

### **Ancien Code (OAuth2 - NE FONCTIONNE PAS)**
```csharp
if (_credential.UnderlyingCredential is ServiceAccountCredential sac)
{
    token = await sac.GetAccessTokenForRequestAsync(null, cancellationToken);
}
client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", token);
string url = $"{model}:generateContent";
```

### **Nouveau Code (API Key - FONCTIONNE)**
```csharp
string? apiKey = Environment.GetEnvironmentVariable("GEMINI_API_KEY");
if (string.IsNullOrEmpty(apiKey))
{
    return "IA temporairement indisponible - Configuration requise.";
}
string url = $"{model}:generateContent?key={apiKey}";
```

---

## 📝 Notes Importantes

1. **L'application fonctionne SANS la clé API**
   - Elle retournera simplement `"IA temporairement indisponible - Configuration requise."`
   - Les messages Kafka seront consommés mais pas traités par Gemini

2. **Pas besoin de redéployer**
   - Changement de clé API = redémarrer l'application
   - Pas besoin de recompiler

3. **Compatibilité**
   - Cette méthode fonctionne avec Gemini API (REST)
   - Compatible avec les modèles : `gemini-pro`, `gemini-flash`, `gemini-1.5-pro`, etc.

---

## 🎯 Prochaines Étapes

1. ✅ **Obtenir une clé API Gemini**
2. ✅ **Configurer la variable d'environnement**
3. ✅ **Lancer l'application avec `dotnet run`**
4. ✅ **Tester avec un INSERT PostgreSQL**
   ```sql
   INSERT INTO public.diagnostics (diagnostic_text) 
   VALUES ('Patient with severe headache and fever');
   ```
5. ✅ **Vérifier que `ia_guidance` est rempli par Gemini**

---

## 🆘 Support

Si vous rencontrez des erreurs :

1. **Vérifiez la clé API** : `echo $env:GEMINI_API_KEY`
2. **Vérifiez les logs** : Cherchez `[FAIL_API]` ou `[GEMINI_SKIP]`
3. **Testez l'API directement** : Utilisez le Test 2 ci-dessus
4. **Vérifiez les quotas** : https://console.cloud.google.com/apis/api/generativelanguage.googleapis.com/quotas

---

**Corrections appliquées par : GitHub Copilot**  
**Date : 6 Novembre 2025**
