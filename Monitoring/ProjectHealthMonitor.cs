// Fichier: Monitoring/ProjectHealthMonitor.cs
using System.Diagnostics;
using System.Collections.Concurrent;
using PrototypeGemini.Security;

namespace PrototypeGemini.Monitoring
{
    /// <summary>
    /// Moniteur de santé du projet en temps réel.
    /// Détecte les anomalies, erreurs, problèmes de performance, menaces de sécurité.
    /// </summary>
    public sealed class ProjectHealthMonitor : BackgroundService
    {
        private readonly ILogger<ProjectHealthMonitor> _logger;
        private readonly AuditLogger _auditLogger;
        private readonly ConcurrentBag<HealthIssue> _activeIssues = new();
        private readonly PerformanceCounter? _cpuCounter;
        private readonly PerformanceCounter? _memoryCounter;
        private HealthStatus _currentStatus = HealthStatus.Healthy;
        private DateTime _lastHealthCheckUtc = DateTime.UtcNow;

        public ProjectHealthMonitor(ILogger<ProjectHealthMonitor> logger, AuditLogger auditLogger)
        {
            _logger = logger;
            _auditLogger = auditLogger;

            // Compteurs de performance (Windows uniquement)
            try
            {
                if (OperatingSystem.IsWindows())
                {
                    _cpuCounter = new PerformanceCounter("Processor", "% Processor Time", "_Total", true);
                    _memoryCounter = new PerformanceCounter("Memory", "Available MBytes", true);
                }
            }
            catch (Exception ex)
            {
                _logger.LogWarning("⚠️ Impossible d'initialiser les compteurs de performance: {Error}", ex.Message);
            }
        }

        protected override async Task ExecuteAsync(CancellationToken stoppingToken)
        {
            _logger.LogInformation("🏥 Moniteur de santé du projet démarré");

            await Task.Delay(5000, stoppingToken); // Attendre le démarrage complet

            while (!stoppingToken.IsCancellationRequested)
            {
                try
                {
                    await PerformHealthCheckAsync();
                    await DisplayHealthReportAsync();
                    
                    // Vérification toutes les 10 secondes
                    await Task.Delay(TimeSpan.FromSeconds(10), stoppingToken);
                }
                catch (OperationCanceledException)
                {
                    break;
                }
                catch (Exception ex)
                {
                    _logger.LogError(ex, "❌ Erreur dans le moniteur de santé");
                }
            }

            _logger.LogInformation("🛑 Moniteur de santé arrêté");
        }

        /// <summary>
        /// Effectue une vérification complète de la santé du projet.
        /// </summary>
        private async Task PerformHealthCheckAsync()
        {
            _lastHealthCheckUtc = DateTime.UtcNow;
            _activeIssues.Clear();

            // 1. Vérification de la mémoire
            var memoryUsageMb = Process.GetCurrentProcess().WorkingSet64 / 1024 / 1024;
            if (memoryUsageMb > 500)
            {
                _activeIssues.Add(new HealthIssue
                {
                    Severity = IssueSeverity.Warning,
                    Category = "Performance",
                    Message = $"Utilisation mémoire élevée: {memoryUsageMb} MB",
                    Recommendation = "Vérifier les fuites mémoire, optimiser les caches"
                });
            }

            // 2. Vérification CPU (Windows uniquement)
            if (OperatingSystem.IsWindows() && _cpuCounter != null)
            {
                var cpuUsage = _cpuCounter.NextValue();
                await Task.Delay(100); // Délai nécessaire pour obtenir une valeur précise
                cpuUsage = _cpuCounter.NextValue();
                
                if (cpuUsage > 80)
                {
                    _activeIssues.Add(new HealthIssue
                    {
                        Severity = IssueSeverity.Warning,
                        Category = "Performance",
                        Message = $"Utilisation CPU élevée: {cpuUsage:F1}%",
                        Recommendation = "Analyser les tâches en cours, optimiser les boucles"
                    });
                }
            }

            // 3. Vérification des threads
            var threadCount = Process.GetCurrentProcess().Threads.Count;
            if (threadCount > 100)
            {
                _activeIssues.Add(new HealthIssue
                {
                    Severity = IssueSeverity.Warning,
                    Category = "Performance",
                    Message = $"Nombre de threads élevé: {threadCount}",
                    Recommendation = "Vérifier les tâches asynchrones non terminées"
                });
            }

            // 4. Vérification des handles
            var handleCount = Process.GetCurrentProcess().HandleCount;
            if (handleCount > 1000)
            {
                _activeIssues.Add(new HealthIssue
                {
                    Severity = IssueSeverity.Warning,
                    Category = "Resources",
                    Message = $"Nombre de handles élevé: {handleCount}",
                    Recommendation = "Vérifier la fermeture des ressources (fichiers, connexions)"
                });
            }

            // 5. Vérification du uptime
            var uptime = DateTime.UtcNow - Process.GetCurrentProcess().StartTime.ToUniversalTime();
            if (uptime.TotalHours > 24)
            {
                _activeIssues.Add(new HealthIssue
                {
                    Severity = IssueSeverity.Info,
                    Category = "Maintenance",
                    Message = $"Application en cours depuis {uptime.TotalHours:F1} heures",
                    Recommendation = "Planifier un redémarrage pour libérer les ressources"
                });
            }

            // 6. Vérification de l'espace disque
            var driveInfo = new DriveInfo(Path.GetPathRoot(Environment.CurrentDirectory)!);
            var freeSpaceGb = driveInfo.AvailableFreeSpace / 1024 / 1024 / 1024;
            if (freeSpaceGb < 5)
            {
                _activeIssues.Add(new HealthIssue
                {
                    Severity = IssueSeverity.Critical,
                    Category = "Storage",
                    Message = $"Espace disque faible: {freeSpaceGb} GB",
                    Recommendation = "Libérer de l'espace disque immédiatement"
                });
            }

            // 7. Vérification des certificats SSL
            await CheckSslCertificatesAsync();

            // 8. Vérification des logs d'erreur récents
            await CheckRecentErrorsAsync();

            // Déterminer le statut global
            UpdateOverallHealthStatus();
        }

        /// <summary>
        /// Vérifie les certificats SSL/TLS.
        /// </summary>
        private async Task CheckSslCertificatesAsync()
        {
            var certPath = Path.Combine(Directory.GetCurrentDirectory(), "kafka_certs", "service.cert");
            if (!File.Exists(certPath))
            {
                _activeIssues.Add(new HealthIssue
                {
                    Severity = IssueSeverity.Critical,
                    Category = "Security",
                    Message = "Certificat Kafka manquant",
                    Recommendation = "Télécharger le certificat depuis Aiven Console"
                });
                return;
            }

            try
            {
                using var cert = System.Security.Cryptography.X509Certificates.X509CertificateLoader.LoadCertificateFromFile(certPath);
                var daysUntilExpiry = (cert.NotAfter - DateTime.UtcNow).TotalDays;

                if (daysUntilExpiry < 0)
                {
                    _activeIssues.Add(new HealthIssue
                    {
                        Severity = IssueSeverity.Critical,
                        Category = "Security",
                        Message = $"Certificat SSL EXPIRÉ depuis {-daysUntilExpiry:F0} jours",
                        Recommendation = "Renouveler le certificat immédiatement"
                    });
                }
                else if (daysUntilExpiry < 30)
                {
                    _activeIssues.Add(new HealthIssue
                    {
                        Severity = IssueSeverity.Warning,
                        Category = "Security",
                        Message = $"Certificat SSL expire dans {daysUntilExpiry:F0} jours",
                        Recommendation = "Planifier le renouvellement du certificat"
                    });
                }
            }
            catch (Exception ex)
            {
                _activeIssues.Add(new HealthIssue
                {
                    Severity = IssueSeverity.Error,
                    Category = "Security",
                    Message = $"Certificat SSL invalide: {ex.Message}",
                    Recommendation = "Vérifier l'intégrité du fichier certificat"
                });
            }

            await Task.CompletedTask;
        }

        /// <summary>
        /// Vérifie les erreurs récentes dans les logs.
        /// </summary>
        private async Task CheckRecentErrorsAsync()
        {
            // TODO: Parser les logs Serilog pour détecter les erreurs récentes
            await Task.CompletedTask;
        }

        /// <summary>
        /// Met à jour le statut global de santé.
        /// </summary>
        private void UpdateOverallHealthStatus()
        {
            var previousStatus = _currentStatus;

            if (_activeIssues.Any(i => i.Severity == IssueSeverity.Critical))
                _currentStatus = HealthStatus.Critical;
            else if (_activeIssues.Any(i => i.Severity == IssueSeverity.Error))
                _currentStatus = HealthStatus.Unhealthy;
            else if (_activeIssues.Any(i => i.Severity == IssueSeverity.Warning))
                _currentStatus = HealthStatus.Degraded;
            else
                _currentStatus = HealthStatus.Healthy;

            if (_currentStatus != previousStatus)
            {
                _logger.LogWarning("🔄 Statut de santé changé: {Previous} → {Current}", 
                    previousStatus, _currentStatus);
                
                _ = _auditLogger.LogEventAsync(
                    "HEALTH_STATUS_CHANGE",
                    $"Status changed from {previousStatus} to {_currentStatus}",
                    metadata: new Dictionary<string, object>
                    {
                        ["PreviousStatus"] = previousStatus.ToString(),
                        ["NewStatus"] = _currentStatus.ToString(),
                        ["IssueCount"] = _activeIssues.Count
                    }
                );
            }
        }

        /// <summary>
        /// Affiche un rapport de santé complet dans la console.
        /// </summary>
        private Task DisplayHealthReportAsync()
        {
            var statusIcon = _currentStatus switch
            {
                HealthStatus.Healthy => "✅",
                HealthStatus.Degraded => "⚠️",
                HealthStatus.Unhealthy => "❌",
                HealthStatus.Critical => "🚨",
                _ => "❓"
            };

            var process = Process.GetCurrentProcess();
            var memoryMb = process.WorkingSet64 / 1024 / 1024;
            var threads = process.Threads.Count;
            var handles = process.HandleCount;
            var uptime = DateTime.UtcNow - process.StartTime.ToUniversalTime();

            _logger.LogInformation(
                "{Icon} SANTÉ DU PROJET: {Status} | Mémoire: {Memory}MB | Threads: {Threads} | Handles: {Handles} | Uptime: {Uptime}",
                statusIcon, _currentStatus, memoryMb, threads, handles, uptime.ToString(@"hh\:mm\:ss")
            );

            if (_activeIssues.Count > 0)
            {
                _logger.LogWarning("⚠️ {Count} PROBLÈME(S) DÉTECTÉ(S):", _activeIssues.Count);
                
                foreach (var issue in _activeIssues.OrderByDescending(i => i.Severity))
                {
                    var severityIcon = issue.Severity switch
                    {
                        IssueSeverity.Critical => "🚨",
                        IssueSeverity.Error => "❌",
                        IssueSeverity.Warning => "⚠️",
                        IssueSeverity.Info => "ℹ️",
                        _ => "•"
                    };

                    _logger.LogWarning("  {Icon} [{Category}] {Message}", 
                        severityIcon, issue.Category, issue.Message);
                    _logger.LogInformation("    💡 Recommandation: {Recommendation}", 
                        issue.Recommendation);
                }
            }

            return Task.CompletedTask;
        }

        /// <summary>
        /// Rapporte un problème détecté par un autre composant.
        /// </summary>
        public void ReportIssue(string category, string message, string recommendation, IssueSeverity severity = IssueSeverity.Warning)
        {
            _activeIssues.Add(new HealthIssue
            {
                Severity = severity,
                Category = category,
                Message = message,
                Recommendation = recommendation,
                Timestamp = DateTime.UtcNow
            });

            UpdateOverallHealthStatus();
        }

        public HealthStatus CurrentStatus => _currentStatus;
        public IReadOnlyCollection<HealthIssue> ActiveIssues => _activeIssues.ToArray();
    }

    public enum HealthStatus
    {
        Healthy,
        Degraded,
        Unhealthy,
        Critical
    }

    public enum IssueSeverity
    {
        Info,
        Warning,
        Error,
        Critical
    }

    public class HealthIssue
    {
        public IssueSeverity Severity { get; set; }
        public string Category { get; set; } = string.Empty;
        public string Message { get; set; } = string.Empty;
        public string Recommendation { get; set; } = string.Empty;
        public DateTime Timestamp { get; set; } = DateTime.UtcNow;
    }
}
