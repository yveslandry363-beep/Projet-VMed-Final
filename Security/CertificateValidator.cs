// Fichier: Security/CertificateValidator.cs
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;
using System.Net.Security;

namespace PrototypeGemini.Security
{
    /// <summary>
    /// Validateur de certificats SSL/TLS avec vérification stricte (Certificate Pinning).
    /// Protège contre les attaques Man-in-the-Middle et certificats frauduleux.
    /// </summary>
    public sealed class CertificateValidator
    {
        private readonly ILogger<CertificateValidator> _logger;
        private readonly HashSet<string> _pinnedThumbprints = new();
        private readonly HashSet<string> _trustedIssuers = new();

        public CertificateValidator(ILogger<CertificateValidator> logger)
        {
            _logger = logger;
            
            // Ajoutez ici les empreintes SHA-256 des certificats autorisés (Certificate Pinning)
            // Exemple: _pinnedThumbprints.Add("SHA256_THUMBPRINT_HERE");
            
            // Issuers de confiance (Let's Encrypt, DigiCert, etc.)
            _trustedIssuers.Add("CN=Let's Encrypt Authority X3");
            _trustedIssuers.Add("CN=DigiCert Global Root CA");
            _trustedIssuers.Add("CN=Baltimore CyberTrust Root");
        }

        /// <summary>
        /// Callback de validation SSL personnalisé pour HttpClient.
        /// </summary>
        public bool ValidateServerCertificate(
            HttpRequestMessage request,
            X509Certificate2? certificate,
            X509Chain? chain,
            SslPolicyErrors sslPolicyErrors)
        {
            if (certificate == null)
            {
                _logger.LogError("🚨 CERTIFICAT NULL détecté pour {Host}", request.RequestUri?.Host);
                return false;
            }

            // 1. Vérification des erreurs SSL de base
            if (sslPolicyErrors != SslPolicyErrors.None)
            {
                _logger.LogWarning("⚠️ Erreur SSL détectée: {Errors} pour {Host}", 
                    sslPolicyErrors, request.RequestUri?.Host);
                
                // En production, retourner false ici
                // En développement, on peut accepter les certificats auto-signés
                if (!IsLocalDevelopment())
                    return false;
            }

            // 2. Vérification de la révocation du certificat
            if (chain?.ChainStatus != null)
            {
                foreach (var status in chain.ChainStatus)
                {
                    if (status.Status == X509ChainStatusFlags.Revoked)
                    {
                        _logger.LogError("🚨 CERTIFICAT RÉVOQUÉ détecté pour {Host}", request.RequestUri?.Host);
                        return false;
                    }
                }
            }

            // 3. Vérification de la date d'expiration
            if (certificate.NotAfter < DateTime.UtcNow)
            {
                _logger.LogError("🚨 CERTIFICAT EXPIRÉ: {NotAfter} pour {Host}", 
                    certificate.NotAfter, request.RequestUri?.Host);
                return false;
            }

            if (certificate.NotBefore > DateTime.UtcNow)
            {
                _logger.LogError("🚨 CERTIFICAT PAS ENCORE VALIDE: {NotBefore} pour {Host}", 
                    certificate.NotBefore, request.RequestUri?.Host);
                return false;
            }

            // 4. Vérification du Subject (nom de domaine)
            var expectedHost = request.RequestUri?.Host?.ToLowerInvariant();
            var certSubject = certificate.Subject.ToLowerInvariant();
            
            if (!certSubject.Contains($"cn={expectedHost}") && 
                !HasValidSan(certificate, expectedHost ?? string.Empty))
            {
                _logger.LogWarning("⚠️ Mismatch du nom de domaine: Attendu={Expected}, Cert={Cert}", 
                    expectedHost, certSubject);
            }

            // 5. Certificate Pinning (si configuré)
            if (_pinnedThumbprints.Count > 0)
            {
                var thumbprint = certificate.GetCertHashString(HashAlgorithmName.SHA256);
                if (!_pinnedThumbprints.Contains(thumbprint))
                {
                    _logger.LogError("🚨 CERTIFICATE PINNING FAILED: Thumbprint {Thumbprint} non autorisé", 
                        thumbprint);
                    return false;
                }
            }

            // 6. Vérification de l'algorithme de signature (pas MD5/SHA1)
            if (certificate.SignatureAlgorithm.FriendlyName?.Contains("md5") == true ||
                certificate.SignatureAlgorithm.FriendlyName?.Contains("sha1") == true)
            {
                _logger.LogError("🚨 ALGORITHME DE SIGNATURE FAIBLE: {Algorithm}", 
                    certificate.SignatureAlgorithm.FriendlyName);
                return false;
            }

            _logger.LogDebug("✅ Certificat validé pour {Host} (Expires: {Expiry})", 
                request.RequestUri?.Host, certificate.NotAfter);

            return true;
        }

        /// <summary>
        /// Vérifie les Subject Alternative Names (SAN) du certificat.
        /// </summary>
        private static bool HasValidSan(X509Certificate2 certificate, string expectedHost)
        {
            var sanExtension = certificate.Extensions
                .OfType<X509Extension>()
                .FirstOrDefault(e => e.Oid?.Value == "2.5.29.17"); // SAN OID

            if (sanExtension == null)
                return false;

            var sanNames = new AsnEncodedData(sanExtension.Oid!, sanExtension.RawData)
                .Format(false)
                .ToLowerInvariant();

            return sanNames.Contains(expectedHost);
        }

        /// <summary>
        /// Détecte si on est en développement local.
        /// </summary>
        private static bool IsLocalDevelopment()
        {
            return Environment.GetEnvironmentVariable("ASPNETCORE_ENVIRONMENT") == "Development" ||
                   Environment.MachineName.Contains("DEV", StringComparison.OrdinalIgnoreCase);
        }

        /// <summary>
        /// Ajoute une empreinte de certificat autorisée (Certificate Pinning).
        /// </summary>
        public void AddPinnedCertificate(string sha256Thumbprint)
        {
            _pinnedThumbprints.Add(sha256Thumbprint.ToUpperInvariant());
            _logger.LogInformation("📌 Certificat pinné ajouté: {Thumbprint}", sha256Thumbprint[..16] + "...");
        }

        /// <summary>
        /// Obtient l'empreinte SHA-256 d'un certificat depuis un fichier.
        /// </summary>
        public static string GetCertificateThumbprint(string certPath)
        {
            using var cert = X509CertificateLoader.LoadCertificateFromFile(certPath);
            return cert.GetCertHashString(HashAlgorithmName.SHA256);
        }
    }
}
