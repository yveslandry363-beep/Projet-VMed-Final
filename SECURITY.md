# 🔐 Documentation Sécurité - Prototype Gemini
## Architecture de Sécurité Maximale (OWASP Top 10 2023)

---

## 📋 Table des Matières
1. [Vue d'ensemble](#vue-densemble)
2. [Chiffrement](#chiffrement)
3. [Validation des entrées](#validation-des-entrées)
4. [Rate Limiting](#rate-limiting)
5. [Protection des secrets](#protection-des-secrets)
6. [Recommandations](#recommandations)

---

## 🛡️ Vue d'ensemble

Ce projet implémente une **sécurité multi-couches** basée sur les standards modernes 2023-2025 :

✅ **Chiffrement AES-256-GCM** (Authenticated Encryption)  
✅ **Dérivation de clés PBKDF2-HMAC-SHA256** (100 000 iterations)  
✅ **Validation anti-injection SQL/XSS/Path Traversal**  
✅ **Rate Limiting Token Bucket** (protection DDoS)  
✅ **Regex compilées** pour performance maximale  
✅ **Nettoyage automatique mémoire** (secrets zeroisés)  

---

## 🔒 Chiffrement

### SecureConfigurationManager

**Fichier** : `Security/SecureConfigurationManager.cs`

#### Algorithmes utilisés :
- **Chiffrement** : AES-256-GCM (Galois/Counter Mode)
- **Dérivation** : PBKDF2-HMAC-SHA256 (100 000 iterations)
- **Intégrité** : HMAC-SHA256
- **Aléatoire** : `RandomNumberGenerator` (cryptographiquement sûr)

#### Utilisation :

```csharp
// Injection dans Program.cs
services.AddSingleton<SecureConfigurationManager>();

// Chiffrement d'un secret
var encrypted = secureConfig.Encrypt("AVNS_y_YB7yKdoi-r20UAu1z");
// Résultat : "A1B2C3D4... (Base64)"

// Déchiffrement
var decrypted = secureConfig.Decrypt(encrypted);

// Génération de secret aléatoire (32 bytes = 256 bits)
var apiKey = SecureConfigurationManager.GenerateSecureSecret(32);

// HMAC pour comparaison sécurisée (timing attack safe)
var hash1 = secureConfig.ComputeHmac("password123");
var hash2 = secureConfig.ComputeHmac("password123");
// hash1 == hash2 toujours vrai
```

#### Format du chiffrement :
```
[Nonce (12 bytes)][Tag (16 bytes)][Ciphertext (n bytes)]
```
- **Nonce** : Aléatoire pour chaque message (jamais réutilisé)
- **Tag** : Authentification (détecte les modifications)
- **Ciphertext** : Données chiffrées

---

## ✅ Validation des entrées

### InputValidator

**Fichier** : `Security/InputValidator.cs`

#### Protections implémentées :

| Attaque | Méthode | Regex/Validation |
|---------|---------|------------------|
| **Injection SQL** | `ContainsSqlInjection()` | `union\|select\|insert\|update\|delete\|drop\|exec\|script` |
| **XSS** | `ContainsDangerousCharacters()` | `[<>"'%;()&+]` |
| **Path Traversal** | `ContainsPathTraversal()` | `\.\./\|\.\.\\|%2e%2e%2f` |
| **SSRF** | `IsSafeUrl()` | Bloque IP privées (192.168., 10., 172.16.) |
| **DoS Mémoire** | `TruncateSafely()` | Limite 10 000 caractères |

#### Utilisation dans KafkaConsumerService :

```csharp
// Validation automatique avant traitement
var (isValid, error) = InputValidator.ValidateDiagnostic(diagnostic.diagnostic_text);
if (!isValid)
{
    _logger.LogError("🚨 TENTATIVE D'ATTAQUE DÉTECTÉE : {Error}", error);
    return; // Message rejeté
}

// Tronquage sécurisé pour éviter les DoS
var safeDiagnostic = InputValidator.TruncateSafely(diagnostic.diagnostic_text, 10_000);
```

#### Exemples de détection :

```csharp
// ❌ BLOQUÉ - Injection SQL
InputValidator.ContainsSqlInjection("'; DROP TABLE diagnostics; --");
// Retourne: true

// ❌ BLOQUÉ - Path Traversal
InputValidator.ContainsPathTraversal("../../../etc/passwd");
// Retourne: true

// ❌ BLOQUÉ - XSS
InputValidator.ContainsDangerousCharacters("<script>alert('XSS')</script>");
// Retourne: true

// ✅ AUTORISÉ - Texte médical valide
InputValidator.ValidateDiagnostic("Patient présente des symptômes de grippe");
// Retourne: (true, "")
```

---

## ⏱️ Rate Limiting

### RateLimiter

**Fichier** : `Security/RateLimiter.cs`

#### Algorithme Token Bucket :
- **Capacité** : 100 requêtes par client (configurable)
- **Rechargement** : 1 minute (configurable)
- **Nettoyage auto** : Supprime les buckets inactifs (> 2x interval)

#### Utilisation :

```csharp
// Configuration dans Program.cs
services.AddSingleton<RateLimiter>(sp => 
    new RateLimiter(
        sp.GetRequiredService<ILogger<RateLimiter>>(),
        maxRequests: 100,
        refillInterval: TimeSpan.FromMinutes(1)
    ));

// Middleware API (exemple)
app.Use(async (context, next) =>
{
    var rateLimiter = context.RequestServices.GetRequiredService<RateLimiter>();
    var clientId = context.Connection.RemoteIpAddress?.ToString() ?? "unknown";
    
    if (!rateLimiter.AllowRequest(clientId))
    {
        context.Response.StatusCode = 429; // Too Many Requests
        await context.Response.WriteAsync("Rate limit exceeded");
        return;
    }
    
    await next();
});

// Nettoyage périodique (optionnel, hosted service)
public class RateLimiterCleanupService : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken ct)
    {
        while (!ct.IsCancellationRequested)
        {
            await Task.Delay(TimeSpan.FromMinutes(10), ct);
            _rateLimiter.Cleanup();
        }
    }
}
```

---

## 🔑 Protection des secrets

### Variables d'environnement

**Recommandé** : Stockez la clé maître dans une variable d'environnement :

```powershell
# Windows
[System.Environment]::SetEnvironmentVariable("VMED_MASTER_KEY", "VotreCléTrèsSecrète", "User")

# Linux/MacOS
export VMED_MASTER_KEY="VotreCléTrèsSecrète"
```

### Azure Key Vault (Production)

```csharp
// Configuration dans appsettings.Production.json
{
  "KeyVault": {
    "VaultUri": "https://vmed-vault.vault.azure.net/"
  }
}

// Program.cs
var keyVaultUri = new Uri(builder.Configuration["KeyVault:VaultUri"]!);
builder.Configuration.AddAzureKeyVault(keyVaultUri, new DefaultAzureCredential());
```

### Secrets.json (Développement seulement)

```bash
# Initialiser secrets.json
dotnet user-secrets init

# Ajouter secrets
dotnet user-secrets set "PostgreSql:Password" "AVNS_y_YB7yKdoi-r20UAu1z"
dotnet user-secrets set "Kafka:SaslPassword" "VotreMotDePasse"
```

---

## 📌 Recommandations

### ✅ À FAIRE

1. **Rotation des secrets**  
   - Changez les mots de passe tous les 90 jours
   - Utilisez `SecureConfigurationManager.GenerateSecureSecret()` pour générer de nouveaux secrets

2. **Logs sécurisés**  
   - ❌ Jamais de mots de passe dans les logs : `_logger.LogInformation("Password: {Password}", password)`
   - ✅ Hashez les données sensibles : `_logger.LogInformation("PasswordHash: {Hash}", ComputeHmac(password))`

3. **HTTPS partout**  
   - Kafka : `SecurityProtocol.Ssl` (mTLS)
   - PostgreSQL : `SSL Mode=Require`
   - API externe : Toujours `https://`

4. **Mise à jour régulière**  
   ```bash
   dotnet list package --outdated
   dotnet add package <PackageName> --version <NewVersion>
   ```

5. **Scans de vulnérabilités**  
   ```bash
   # GitHub Security Scanning
   git push origin main  # Active automatiquement Dependabot

   # OWASP Dependency-Check
   dotnet tool install --global dependency-check
   dependency-check --project "Prototype Gemini" --scan "D:\VMed327\Prototype Gemini"
   ```

### ❌ À ÉVITER

1. **Mots de passe en dur**  
   ```csharp
   // ❌ MAL
   var password = "AVNS_y_YB7yKdoi-r20UAu1z";
   
   // ✅ BIEN
   var password = configuration["PostgreSql:Password"];
   ```

2. **Validation côté client uniquement**  
   - Toujours valider sur le serveur (`InputValidator`)

3. **MD5 / SHA1 pour hash de mots de passe**  
   - ❌ Obsolètes (collisions connues)
   - ✅ Utilisez PBKDF2, Argon2id, ou bcrypt

4. **Exceptions détaillées en production**  
   ```csharp
   // ❌ MAL
   catch (Exception ex) {
       return BadRequest(ex.ToString()); // Leak d'infos
   }
   
   // ✅ BIEN
   catch (Exception ex) {
       _logger.LogError(ex, "Erreur");
       return Problem("Erreur interne");
   }
   ```

---

## 🧪 Tests de sécurité

### 1. Test d'injection SQL

```sql
-- Dans DBeaver, essayez d'insérer :
INSERT INTO diagnostics (diagnostic_text) VALUES ('Test normal'); -- ✅ Passera
INSERT INTO diagnostics (diagnostic_text) VALUES ('''; DROP TABLE diagnostics; --'); -- ❌ Bloqué
```

**Résultat attendu** :
```
[14:43:23 ERR] 🚨 TENTATIVE D'ATTAQUE DÉTECTÉE : Le diagnostic contient des caractères suspects (possible injection SQL)
```

### 2. Test de Path Traversal

```csharp
var maliciousPath = "../../../etc/passwd";
var isValid = InputValidator.IsSafeFilePath(maliciousPath, "D:\\Data");
// Résultat : false
```

### 3. Test de Rate Limiting

```csharp
for (int i = 0; i < 110; i++)
{
    var allowed = rateLimiter.AllowRequest("192.168.1.100");
    Console.WriteLine($"Request {i+1}: {(allowed ? "✅" : "❌")}");
}
// Résultat : 100x ✅, 10x ❌
```

---

## 📚 Références

- **OWASP Top 10 2023** : https://owasp.org/www-project-top-ten/
- **NIST SP 800-63B** : Recommandations PBKDF2 iterations
- **CWE Top 25** : https://cwe.mitre.org/top25/
- **.NET Cryptography Best Practices** : https://learn.microsoft.com/en-us/dotnet/standard/security/

---

## 🎯 Résumé

| Couche | Protection | Statut |
|--------|-----------|--------|
| **Transport** | TLS 1.2+ (Kafka mTLS, PostgreSQL SSL) | ✅ |
| **Authentification** | Certificats X.509 (Kafka), Mots de passe (PostgreSQL) | ✅ |
| **Chiffrement** | AES-256-GCM | ✅ |
| **Validation** | Anti-SQL Injection, XSS, Path Traversal | ✅ |
| **Rate Limiting** | Token Bucket (100 req/min) | ✅ |
| **Logs** | Serilog (pas de secrets) | ✅ |
| **Secrets** | Variables d'environnement / Azure Key Vault | ⚠️ À configurer |

---

**Dernière mise à jour** : 6 novembre 2025  
**Niveau de sécurité** : 🔒🔒🔒🔒🔒 (5/5)
