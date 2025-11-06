// Fichier: Security/SecureConfigurationManager.cs
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Microsoft.Extensions.Configuration;

namespace PrototypeGemini.Security
{
    /// <summary>
    /// Gestionnaire de configuration sécurisé avec chiffrement AES-256-GCM.
    /// Protège les secrets sensibles (mots de passe, clés API, certificats).
    /// </summary>
    public sealed class SecureConfigurationManager : IDisposable
    {
        private readonly byte[] _masterKey;
        private readonly ILogger<SecureConfigurationManager> _logger;
        private readonly Dictionary<string, byte[]> _encryptedSecrets = new();
        private bool _disposed;

        public SecureConfigurationManager(IConfiguration configuration, ILogger<SecureConfigurationManager> logger)
        {
            _logger = logger;
            
            // Génération de la clé maître à partir de variables d'environnement + machine ID
            var envKey = Environment.GetEnvironmentVariable("VMED_MASTER_KEY");
            var machineId = Environment.MachineName + Environment.UserName;
            
            _masterKey = DeriveKey(envKey ?? machineId, "PrototypeGemini.v1");
            
            _logger.LogInformation("🔐 SecureConfigurationManager initialisé avec chiffrement AES-256-GCM");
        }

        /// <summary>
        /// Chiffre une valeur sensible avec AES-256-GCM (Authenticated Encryption).
        /// </summary>
        public string Encrypt(string plaintext)
        {
            if (string.IsNullOrEmpty(plaintext))
                throw new ArgumentException("Le texte à chiffrer ne peut pas être vide", nameof(plaintext));

            using var aes = new AesGcm(_masterKey, AesGcm.TagByteSizes.MaxSize);
            
            var nonce = new byte[AesGcm.NonceByteSizes.MaxSize]; // 12 bytes
            var tag = new byte[AesGcm.TagByteSizes.MaxSize];     // 16 bytes
            var plainBytes = Encoding.UTF8.GetBytes(plaintext);
            var cipherBytes = new byte[plainBytes.Length];
            
            RandomNumberGenerator.Fill(nonce);
            
            aes.Encrypt(nonce, plainBytes, cipherBytes, tag);
            
            // Format: [nonce(12)][tag(16)][ciphertext(n)]
            var result = new byte[nonce.Length + tag.Length + cipherBytes.Length];
            Buffer.BlockCopy(nonce, 0, result, 0, nonce.Length);
            Buffer.BlockCopy(tag, 0, result, nonce.Length, tag.Length);
            Buffer.BlockCopy(cipherBytes, 0, result, nonce.Length + tag.Length, cipherBytes.Length);
            
            return Convert.ToBase64String(result);
        }

        /// <summary>
        /// Déchiffre une valeur chiffrée avec AES-256-GCM.
        /// </summary>
        public string Decrypt(string ciphertext)
        {
            if (string.IsNullOrEmpty(ciphertext))
                throw new ArgumentException("Le texte chiffré ne peut pas être vide", nameof(ciphertext));

            var encryptedData = Convert.FromBase64String(ciphertext);
            
            using var aes = new AesGcm(_masterKey, AesGcm.TagByteSizes.MaxSize);
            
            var nonce = new byte[AesGcm.NonceByteSizes.MaxSize];
            var tag = new byte[AesGcm.TagByteSizes.MaxSize];
            var cipherBytes = new byte[encryptedData.Length - nonce.Length - tag.Length];
            
            Buffer.BlockCopy(encryptedData, 0, nonce, 0, nonce.Length);
            Buffer.BlockCopy(encryptedData, nonce.Length, tag, 0, tag.Length);
            Buffer.BlockCopy(encryptedData, nonce.Length + tag.Length, cipherBytes, 0, cipherBytes.Length);
            
            var plainBytes = new byte[cipherBytes.Length];
            
            aes.Decrypt(nonce, cipherBytes, tag, plainBytes);
            
            return Encoding.UTF8.GetString(plainBytes);
        }

        /// <summary>
        /// Dérive une clé de 256 bits à partir d'un mot de passe avec PBKDF2-HMAC-SHA256.
        /// </summary>
        private static byte[] DeriveKey(string password, string salt)
        {
            const int iterations = 100_000; // NIST recommandation 2023
            const int keySize = 32; // 256 bits
            
            return Rfc2898DeriveBytes.Pbkdf2(
                password,
                Encoding.UTF8.GetBytes(salt),
                iterations,
                HashAlgorithmName.SHA256,
                keySize);
        }

        /// <summary>
        /// Génère un secret aléatoire cryptographiquement sûr.
        /// </summary>
        public static string GenerateSecureSecret(int lengthInBytes = 32)
        {
            var bytes = new byte[lengthInBytes];
            RandomNumberGenerator.Fill(bytes);
            return Convert.ToBase64String(bytes);
        }

        /// <summary>
        /// Hache une valeur avec HMAC-SHA256 pour comparaison sécurisée.
        /// </summary>
        public string ComputeHmac(string data)
        {
            using var hmac = new HMACSHA256(_masterKey);
            var hash = hmac.ComputeHash(Encoding.UTF8.GetBytes(data));
            return Convert.ToBase64String(hash);
        }

        public void Dispose()
        {
            if (!_disposed)
            {
                // Nettoie la clé maître de la mémoire
                Array.Clear(_masterKey, 0, _masterKey.Length);
                _disposed = true;
                _logger.LogInformation("🔒 SecureConfigurationManager disposé et clés effacées de la mémoire");
            }
        }
    }
}
