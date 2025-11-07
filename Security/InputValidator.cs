// Fichier: Security/InputValidator.cs
using System.Collections.Concurrent;
using System.Text.RegularExpressions;
using System.Security;

namespace PrototypeGemini.Security
{
    /// <summary>
    /// Validateur d'entrées pour prévenir les injections SQL, XSS, Path Traversal, etc.
    /// Basé sur OWASP Top 10 2023.
    /// </summary>
    public static partial class InputValidator
    {
        // --- AMÉLIORATION "JAMAIS VUE": RASP (Runtime Application Self-Protection) ---
        // Analyse comportementale pour détecter les attaques lentes ou les scans de vulnérabilités.
        private static readonly ConcurrentDictionary<string, (int Count, DateTime LastAttempt)> _suspiciousActivityTracker = new();

        // Expressions régulières compilées pour performance maximale
        [GeneratedRegex(@"^[a-zA-Z0-9_\-\.@]{1,100}$", RegexOptions.Compiled)]
        private static partial Regex SafeIdentifierRegex();

        [GeneratedRegex(@"[<>""'%;()&+]", RegexOptions.Compiled)]
        private static partial Regex DangerousCharsRegex();

        [GeneratedRegex(@"(\.\./|\.\.\\|%2e%2e%2f|%2e%2e/|\.\.%2f)", RegexOptions.IgnoreCase | RegexOptions.Compiled)]
        private static partial Regex PathTraversalRegex();

        [GeneratedRegex(@"(union|select|insert|update|delete|drop|exec|script|javascript|onerror)", RegexOptions.IgnoreCase | RegexOptions.Compiled)]
        private static partial Regex SqlInjectionRegex();

        /// <summary>
        /// Valide un identifiant sûr (nom de table, colonne, etc.).
        /// </summary>
        public static bool IsSafeIdentifier(string input)
        {
            if (string.IsNullOrWhiteSpace(input))
                return false;

            return SafeIdentifierRegex().IsMatch(input);
        }

        /// <summary>
        /// Détecte les caractères dangereux pour XSS/injection.
        /// </summary>
        public static bool ContainsDangerousCharacters(string input)
        {
            if (string.IsNullOrEmpty(input))
                return false;

            return DangerousCharsRegex().IsMatch(input);
        }

        /// <summary>
        /// Détecte les tentatives de Path Traversal (../../../etc/passwd).
        /// </summary>
        public static bool ContainsPathTraversal(string input)
        {
            if (string.IsNullOrEmpty(input))
                return false;

            return PathTraversalRegex().IsMatch(input);
        }

        /// <summary>
        /// Détecte les tentatives d'injection SQL basiques.
        /// </summary>
        public static bool ContainsSqlInjection(string input)
        {
            if (string.IsNullOrEmpty(input))
                return false;

            return SqlInjectionRegex().IsMatch(input);
        }

        /// <summary>
        /// Nettoie une chaîne en échappant les caractères HTML dangereux.
        /// </summary>
        public static string SanitizeHtml(string input)
        {
            if (string.IsNullOrEmpty(input))
                return string.Empty;

            return SecurityElement.Escape(input) ?? string.Empty;
        }

        /// <summary>
        /// Valide une URL pour prévenir les SSRF (Server-Side Request Forgery).
        /// </summary>
        public static bool IsSafeUrl(string url, bool allowLocalhost = false)
        {
            if (string.IsNullOrWhiteSpace(url))
                return false;

            if (!Uri.TryCreate(url, UriKind.Absolute, out var uri))
                return false;

            // Bloque les schémas dangereux
            if (uri.Scheme != Uri.UriSchemeHttps && uri.Scheme != Uri.UriSchemeHttp)
                return false;

            // Bloque les IP privées et localhost (sauf si explicitement autorisé)
            if (!allowLocalhost)
            {
                var host = uri.Host.ToLowerInvariant();
                if (host == "localhost" || host == "127.0.0.1" || host.StartsWith("192.168.") || 
                    host.StartsWith("10.") || host.StartsWith("172.16."))
                    return false;
            }

            return true;
        }

        /// <summary>
        /// Valide un chemin de fichier pour prévenir l'accès non autorisé.
        /// </summary>
        public static bool IsSafeFilePath(string path, string baseDirectory)
        {
            if (string.IsNullOrWhiteSpace(path) || string.IsNullOrWhiteSpace(baseDirectory))
                return false;

            if (ContainsPathTraversal(path))
                return false;

            try
            {
                var fullPath = Path.GetFullPath(Path.Combine(baseDirectory, path));
                var baseFullPath = Path.GetFullPath(baseDirectory);

                return fullPath.StartsWith(baseFullPath, StringComparison.OrdinalIgnoreCase);
            }
            catch
            {
                return false;
            }
        }

        /// <summary>
        /// Limite la longueur d'une chaîne pour prévenir les DoS par mémoire.
        /// </summary>
        public static string TruncateSafely(string input, int maxLength = 10_000)
        {
            if (string.IsNullOrEmpty(input))
                return string.Empty;

            return input.Length > maxLength ? input[..maxLength] : input;
        }

        /// <summary>
        /// Valide un diagnostic médical (pas de code malveillant, longueur raisonnable).
        /// </summary>
        public static (bool IsValid, string Error) ValidateDiagnostic(string diagnosticText)
        {
            if (string.IsNullOrWhiteSpace(diagnosticText))
                return (false, "Le diagnostic ne peut pas être vide");

            if (diagnosticText.Length > 50_000)
                return (false, "Le diagnostic est trop long (max 50 000 caractères)");

            if (ContainsSqlInjection(diagnosticText))
                return (false, "Le diagnostic contient des caractères suspects (possible injection SQL)");

            // --- AMÉLIORATION RASP ---
            // Si on voit plusieurs tentatives suspectes de la même source en peu de temps, on bloque.
            var sourceIdentifier = "kafka-consumer"; // Dans une API web, ce serait l'IP du client.
            if (IsSuspiciousSequence(sourceIdentifier, ContainsDangerousCharacters(diagnosticText)))
            {
                return (false, "Séquence d'attaques détectée (RASP). Source bloquée temporairement.");
            }
            // --- Fin de l'amélioration ---

            if (ContainsPathTraversal(diagnosticText))
                return (false, "Le diagnostic contient des caractères suspects (possible path traversal)");

            return (true, string.Empty);
        }

        private static bool IsSuspiciousSequence(string source, bool isAttempt)
        {
            var entry = _suspiciousActivityTracker.GetOrAdd(source, (0, DateTime.MinValue));
            if (isAttempt)
            {
                // Si la dernière tentative était il y a moins de 5 minutes, on incrémente. Sinon, on reset.
                if (DateTime.UtcNow - entry.LastAttempt < TimeSpan.FromMinutes(5))
                    entry.Count++;
                else
                    entry.Count = 1;
                
                entry.LastAttempt = DateTime.UtcNow;
                _suspiciousActivityTracker[source] = entry;
            }

            // Si plus de 5 tentatives suspectes en 5 minutes, on considère que c'est un scan.
            return entry.Count > 5;
        }
    }
}
