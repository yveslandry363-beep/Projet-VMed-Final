// Fichier: Security/AuditLogger.cs
using System.Text.Json;
using System.Security.Claims;

namespace PrototypeGemini.Security
{
    /// <summary>
    /// Logger d'audit de sécurité pour traçabilité complète (Compliance GDPR/HIPAA).
    /// Enregistre toutes les opérations sensibles avec horodatage, utilisateur, IP.
    /// </summary>
    public sealed class AuditLogger
    {
        private readonly ILogger<AuditLogger> _logger;
        private readonly string _auditLogPath;
        private readonly SemaphoreSlim _fileLock = new(1, 1);

        public AuditLogger(ILogger<AuditLogger> logger)
        {
            _logger = logger;
            _auditLogPath = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData),
                "VMed327",
                "AuditLogs",
                $"audit_{DateTime.UtcNow:yyyy-MM}.log"
            );

            Directory.CreateDirectory(Path.GetDirectoryName(_auditLogPath)!);
        }

        /// <summary>
        /// Enregistre un événement d'audit.
        /// </summary>
        public async Task LogEventAsync(
            string eventType,
            string action,
            string? userId = null,
            string? ipAddress = null,
            Dictionary<string, object>? metadata = null,
            bool success = true)
        {
            var auditEntry = new AuditEntry
            {
                Timestamp = DateTime.UtcNow,
                EventType = eventType,
                Action = action,
                UserId = userId ?? "SYSTEM",
                IpAddress = ipAddress ?? "N/A",
                Success = success,
                Metadata = metadata ?? new(),
                MachineName = Environment.MachineName,
                ApplicationVersion = typeof(AuditLogger).Assembly.GetName().Version?.ToString() ?? "unknown"
            };

            var json = JsonSerializer.Serialize(auditEntry, new JsonSerializerOptions 
            { 
                WriteIndented = false 
            });

            _logger.LogInformation("📋 AUDIT: {EventType} | {Action} | User={UserId} | Success={Success}", 
                eventType, action, userId, success);

            await _fileLock.WaitAsync();
            try
            {
                await File.AppendAllTextAsync(_auditLogPath, json + Environment.NewLine);
            }
            finally
            {
                _fileLock.Release();
            }
        }

        /// <summary>
        /// Log d'accès aux données sensibles (Diagnostic médical).
        /// </summary>
        public Task LogDataAccessAsync(int diagnosticId, string userId, string action)
        {
            return LogEventAsync(
                "DATA_ACCESS",
                action,
                userId,
                metadata: new Dictionary<string, object>
                {
                    ["DiagnosticId"] = diagnosticId,
                    ["DataType"] = "MedicalDiagnostic"
                }
            );
        }

        /// <summary>
        /// Log de tentative d'attaque détectée.
        /// </summary>
        public Task LogSecurityThreatAsync(string threatType, string details, string? ipAddress = null)
        {
            return LogEventAsync(
                "SECURITY_THREAT",
                threatType,
                userId: "ATTACKER",
                ipAddress: ipAddress,
                metadata: new Dictionary<string, object>
                {
                    ["ThreatDetails"] = details,
                    ["Severity"] = "HIGH"
                },
                success: false
            );
        }

        /// <summary>
        /// Log d'échec d'authentification.
        /// </summary>
        public Task LogAuthenticationFailureAsync(string username, string reason, string? ipAddress = null)
        {
            return LogEventAsync(
                "AUTHENTICATION",
                "LOGIN_FAILED",
                userId: username,
                ipAddress: ipAddress,
                metadata: new Dictionary<string, object>
                {
                    ["FailureReason"] = reason
                },
                success: false
            );
        }

        /// <summary>
        /// Log de modification de configuration sensible.
        /// </summary>
        public Task LogConfigurationChangeAsync(string configKey, string? oldValue, string? newValue, string userId)
        {
            return LogEventAsync(
                "CONFIGURATION",
                "CONFIG_CHANGED",
                userId: userId,
                metadata: new Dictionary<string, object>
                {
                    ["ConfigKey"] = configKey,
                    ["OldValue"] = oldValue ?? "N/A",
                    ["NewValue"] = newValue ?? "N/A"
                }
            );
        }

        private class AuditEntry
        {
            public DateTime Timestamp { get; set; }
            public string EventType { get; set; } = string.Empty;
            public string Action { get; set; } = string.Empty;
            public string UserId { get; set; } = string.Empty;
            public string IpAddress { get; set; } = string.Empty;
            public bool Success { get; set; }
            public Dictionary<string, object> Metadata { get; set; } = new();
            public string MachineName { get; set; } = string.Empty;
            public string ApplicationVersion { get; set; } = string.Empty;
        }
    }
}
