// Fichier: Security/RateLimiter.cs
using System.Diagnostics;
using System.Collections.Concurrent;

namespace PrototypeGemini.Security
{
    /// <summary>
    /// Rate limiter avec algorithme Token Bucket pour protection DDoS.
    /// Limite le nombre de requêtes par IP/utilisateur.
    /// </summary>
    public sealed class RateLimiter
    {
        private readonly ConcurrentDictionary<string, TokenBucket> _buckets = new();
        private readonly int _maxRequests;
        private readonly TimeSpan _refillInterval;
        private readonly ILogger<RateLimiter> _logger;

        public RateLimiter(ILogger<RateLimiter> logger, int maxRequests = 100, TimeSpan? refillInterval = null)
        {
            _logger = logger;
            _maxRequests = maxRequests;
            _refillInterval = refillInterval ?? TimeSpan.FromMinutes(1);
        }

        /// <summary>
        /// Vérifie si une requête est autorisée selon le rate limit.
        /// </summary>
        public bool AllowRequest(string clientId)
        {
            var bucket = _buckets.GetOrAdd(clientId, _ => new TokenBucket(_maxRequests, _refillInterval));

            // --- AMÉLIORATION 5: Sécurité Proactive par Détection d'Anomalies ---
            var (allowed, burstRate) = bucket.TryConsume();
            
            if (!allowed)
            {
                _logger.LogWarning("⚠️ Rate limit dépassé pour le client {ClientId}", clientId);
            }
            else if (burstRate > 5) // Si plus de 5 requêtes en une seconde
            {
                _logger.LogWarning(
                    "[SECURITY_PROACTIVE] Comportement suspect détecté pour le client {ClientId}. Taux de rafale élevé: {BurstRate} req/s.",
                    clientId, burstRate
                );
            }
            
            return allowed;
        }

        /// <summary>
        /// Nettoie les buckets inactifs (pour éviter les fuites mémoire).
        /// </summary>
        public void Cleanup()
        {
            var cutoff = DateTime.UtcNow.Add(-_refillInterval * 2);
            var toRemove = _buckets.Where(kvp => kvp.Value.LastAccess < cutoff).Select(kvp => kvp.Key).ToList();
            
            foreach (var key in toRemove)
            {
                _buckets.TryRemove(key, out _);
            }
            
            if (toRemove.Count > 0)
            {
                _logger.LogDebug("🧹 Nettoyage de {Count} buckets inactifs", toRemove.Count);
            }
        }

        private sealed class TokenBucket
        {
            private readonly int _capacity;
            private readonly TimeSpan _refillInterval;
            private int _tokens;
            private DateTime _lastRefill;
            private readonly object _lock = new();
            private readonly ConcurrentQueue<DateTime> _requestTimestamps = new();

            public DateTime LastAccess { get; private set; }

            public TokenBucket(int capacity, TimeSpan refillInterval)
            {
                _capacity = capacity;
                _refillInterval = refillInterval;
                _tokens = capacity;
                _lastRefill = DateTime.UtcNow;
                LastAccess = DateTime.UtcNow;
            }

            /// <summary>
            /// Tente de consommer un jeton.
            /// </summary>
            /// <returns>Un tuple (bool allowed, double burstRate) où burstRate est le nombre de requêtes dans la dernière seconde.</returns>
            public (bool, double) TryConsume()
            {
                lock (_lock)
                {
                    Refill();
                    LastAccess = DateTime.UtcNow;

                    if (_tokens > 0)
                    {
                        _tokens--;
                        
                        // --- AMÉLIORATION 5: Calcul du taux de rafale ---
                        var now = DateTime.UtcNow;
                        _requestTimestamps.Enqueue(now);
                        while (_requestTimestamps.TryPeek(out var oldest) && (now - oldest).TotalSeconds > 1)
                        {
                            _requestTimestamps.TryDequeue(out _);
                        }
                        // --- Fin de l'amélioration ---

                        return (true, _requestTimestamps.Count);
                    }

                    return (false, _requestTimestamps.Count);
                }
            }

            private void Refill()
            {
                var now = DateTime.UtcNow;
                var elapsed = now - _lastRefill;

                if (elapsed >= _refillInterval)
                {
                    _tokens = _capacity;
                    _lastRefill = now;
                }
            }
        }
    }
}
