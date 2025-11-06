// Fichier: Services/KafkaConsumerService.cs
using Confluent.Kafka;
using Microsoft.FeatureManagement;
using PrototypeGemini.Helpers;
using PrototypeGemini.Interfaces;
using PrototypeGemini.Models;
using PrototypeGemini.Serialization;
using PrototypeGemini.Settings;
using PrototypeGemini.Security;
using System.Collections.Concurrent;
using System.Diagnostics.Metrics;
using System.Text.Json;

namespace PrototypeGemini.Services
{
    public class KafkaConsumerService : BackgroundService
    {
        // ... (Tout le constructeur et les champs sont OK) ...
        private readonly ILogger<KafkaConsumerService> _logger;
        private readonly IServiceProvider _serviceProvider;
        private readonly KafkaSettings _kafkaSettings;
        private readonly IKafkaProducer _dlqProducer;
        private readonly IFeatureManager _featureManager;
        private readonly IConsumer<Ignore, string> _consumer;
        private readonly ConcurrentDictionary<int, DateTime> _recentProcessed = new();
        private readonly Counter<int> _messagesProcessed = Telemetry.MessagesProcessed;
        private readonly Counter<int> _messagesSkipped = Telemetry.MessagesSkipped;
        private readonly Counter<int> _messagesDlq = Telemetry.MessagesDlq;
        private readonly Histogram<double> _processingDuration = Telemetry.ProcessingDuration;

        public KafkaConsumerService(
            IOptions<KafkaSettings> kafkaSettings,
            IServiceProvider serviceProvider,
            ILogger<KafkaConsumerService> logger,
            IKafkaProducer dlqProducer,
            IFeatureManager featureManager)
        {
            _logger = logger;
            _serviceProvider = serviceProvider;
            _kafkaSettings = kafkaSettings.Value;
            _dlqProducer = dlqProducer;
            _featureManager = featureManager;

            // Auto‑détection du mode d'authentification Kafka.
            // Priorité: si SASL creds présents -> SASL_SSL (Plain). Sinon si cert/key présents -> SSL (mTLS). Sinon erreur explicite.
            var certPath = Path.Combine(Directory.GetCurrentDirectory(), "kafka_certs", "service.cert");
            var keyPath = Path.Combine(Directory.GetCurrentDirectory(), "kafka_certs", "service.key");
            bool hasSasl = !string.IsNullOrWhiteSpace(_kafkaSettings.SaslUsername) && !string.IsNullOrWhiteSpace(_kafkaSettings.SaslPassword);
            bool hasMtls = File.Exists(certPath) && File.Exists(keyPath) && !string.IsNullOrWhiteSpace(_kafkaSettings.SslCaLocation);

            var config = new ConsumerConfig
            {
                BootstrapServers = _kafkaSettings.BootstrapServers,
                GroupId = _kafkaSettings.GroupId,
                AutoOffsetReset = _kafkaSettings.AutoOffsetReset,
                EnableAutoCommit = _kafkaSettings.EnableAutoCommit,
                MaxPollIntervalMs = _kafkaSettings.MaxPollIntervalMs
            };

            if (hasSasl)
            {
                _logger.LogInformation("[KAFKA_AUTH] Mode SASL_SSL (PLAIN) détecté (username/password présents).");
                config.SecurityProtocol = SecurityProtocol.SaslSsl;
                config.SaslMechanism = SaslMechanism.Plain;
                config.SaslUsername = _kafkaSettings.SaslUsername;
                config.SaslPassword = _kafkaSettings.SaslPassword;
                if (!string.IsNullOrWhiteSpace(_kafkaSettings.SslCaLocation))
                    config.SslCaLocation = _kafkaSettings.SslCaLocation;
            }
            else if (hasMtls)
            {
                _logger.LogInformation("[KAFKA_AUTH] Mode SSL mTLS détecté (certificat client)." );
                config.SecurityProtocol = SecurityProtocol.Ssl;
                config.SslCaLocation = _kafkaSettings.SslCaLocation;
                config.SslCertificateLocation = certPath;
                config.SslKeyLocation = keyPath;
                config.SslEndpointIdentificationAlgorithm = SslEndpointIdentificationAlgorithm.None;
            }
            else
            {
                var msg = "Aucune configuration Kafka valide trouvée: ni SASL (username/password) ni mTLS (service.cert/service.key + CA).";
                _logger.LogCritical(msg);
                throw new InvalidOperationException(msg);
            }

            _consumer = new ConsumerBuilder<Ignore, string>(config)
                .SetErrorHandler((_, e) => _logger.LogError("[KAFKA_ERR] Erreur Kafka: {Reason}", e.Reason))
                .Build();
        }

        protected override async Task ExecuteAsync(CancellationToken stoppingToken)
        {
            _consumer.Subscribe(_kafkaSettings.Topic);
            _logger.LogInformation("Abonné au topic Kafka: {Topic}", _kafkaSettings.Topic);
            _logger.LogInformation("🔍 GroupId: {GroupId}, AutoOffsetReset: {Reset}", _kafkaSettings.GroupId, _kafkaSettings.AutoOffsetReset);

            _ = Task.Run(() => CleanupCacheLoop(stoppingToken), stoppingToken);

            var pollCount = 0;
            while (!stoppingToken.IsCancellationRequested)
            {
                try
                {
                    pollCount++;
                    if (pollCount % 10 == 0)
                    {
                        _logger.LogDebug("🔄 Poll #{Count} - Attente de messages...", pollCount);
                    }
                    
                    var result = _consumer.Consume(TimeSpan.FromSeconds(5)); // Augmenté de 1s à 5s
                    
                    if (result == null)
                    {
                        if (pollCount % 20 == 0)
                        {
                            _logger.LogWarning("⏳ Aucun message reçu après {Count} polls", pollCount);
                        }
                        continue;
                    }
                    
                    if (result.IsPartitionEOF)
                    {
                        _logger.LogDebug("📭 Fin de partition atteinte (offset {Offset})", result.Offset);
                        continue;
                    }

                    var sw = Stopwatch.StartNew();
                    using var activity = Telemetry.ActivitySource.StartActivity("Kafka ProcessMessage", ActivityKind.Consumer);
                    
                    _logger.LogInformation("Message reçu (Offset {Offset})", result.Offset);

                    try
                    {
                        // LOG DU MESSAGE BRUT COMPLET (pour debug)
                        if (_logger.IsEnabled(LogLevel.Debug))
                        {
                            _logger.LogDebug("📨 Message brut: {Raw}", result.Message.Value);
                        }
                        
                        // Désérialisation : Support des 2 formats Debezium
                        // 1. Format COMPLET (Envelope avec before/after) - anciens messages snapshot
                        // 2. Format SIMPLIFIE (ExtractNewRecordState SMT) - nouveaux messages
                        DiagnosticPayload? diagnostic = null;
                        
                        try
                        {
                            // Tentative Format COMPLET (avec payload.before/after)
                            var msgComplet = JsonSerializer.Deserialize<DebeziumMessage<DiagnosticPayload>>(
                                result.Message.Value, 
                                JsonContext.Default.Options);
                            
                            if (msgComplet?.payload?.after != null)
                            {
                                diagnostic = msgComplet.payload.after;
                                _logger.LogDebug("Format Debezium COMPLET détecté (payload.after)");
                            }
                        }
                        catch (JsonException)
                        {
                            // Tentative Format SIMPLIFIE (ExtractNewRecordState SMT)
                            try
                            {
                                var msgSimplifie = JsonSerializer.Deserialize<DebeziumSimplifiedMessage>(
                                    result.Message.Value, 
                                    JsonContext.Default.Options);
                                
                                if (msgSimplifie?.payload != null)
                                {
                                    diagnostic = msgSimplifie.payload;
                                    _logger.LogDebug("Format Debezium SIMPLIFIE détecté (ExtractNewRecordState)");
                                }
                            }
                            catch (JsonException jex2)
                            {
                                _logger.LogWarning("Message invalide (aucun format Debezium reconnu), envoi vers DLQ. Raw: {Raw}", 
                                    result.Message.Value.Length > 500 ? result.Message.Value[..500] + "..." : result.Message.Value);
                                await HandlePoisonPill(result, "Format Debezium inconnu", jex2);
                                continue;
                            }
                        }
                        
                        if (diagnostic == null || diagnostic.id == 0)
                        {
                            _logger.LogWarning("Message invalide (payload vide ou ID=0), envoi vers DLQ");
                            await HandlePoisonPill(result, "Diagnostic payload null ou ID=0", null);
                            continue;
                        }
                        
                        _logger.LogInformation("📬 Message Debezium reçu: ID={Id}, Text={Text}", 
                            diagnostic.id, diagnostic.diagnostic_text.Length > 50 ? diagnostic.diagnostic_text[..50] + "..." : diagnostic.diagnostic_text);

                        if (_recentProcessed.ContainsKey(diagnostic.id))
                        {
                            _logger.LogWarning("ID {Id} déjà traité récemment, saut.", diagnostic.id);
                            _messagesSkipped.Add(1);
                            CommitOffset(result);
                            continue;
                        }
                        
                        await ProcessMessage(diagnostic);
                        
                        _recentProcessed[diagnostic.id] = DateTime.UtcNow;
                        _messagesProcessed.Add(1);
                        _processingDuration.Record(sw.Elapsed.TotalSeconds);

                        CommitOffset(result);
                    }
                    catch (JsonException jex)
                    {
                        _logger.LogError(jex, "[FAIL_KAFKA] JSON invalide, envoi vers DLQ. Offset {Offset}", result.Offset);
                        await HandlePoisonPill(result, "JSON Invalide", jex);
                    }
                    catch (Exception ex)
                    {
                        _logger.LogError(ex, "Erreur lors du traitement du message. L'offset ne sera PAS commit, nouvelle tentative au prochain poll.");
                    }
                }
                catch (OperationCanceledException)
                {
                    _logger.LogInformation("Arrêt demandé.");
                    break;
                }
                catch (Exception ex)
                {
                    _logger.LogCritical(ex, "Erreur fatale dans la boucle Kafka.");
                    await Task.Delay(2000, stoppingToken);
                }
            }

            _consumer.Close();
            _logger.LogInformation("Consommateur Kafka fermé.");
        }
        
        private async Task ProcessMessage(DiagnosticPayload diagnostic)
        {
            // VALIDATION DE SÉCURITÉ : Empêche les injections SQL et attaques
            var (isValid, error) = PrototypeGemini.Security.InputValidator.ValidateDiagnostic(diagnostic.diagnostic_text);
            if (!isValid)
            {
                _logger.LogError("🚨 TENTATIVE D'ATTAQUE DÉTECTÉE : {Error} - Diagnostic ID {Id}", error, diagnostic.id);
                _messagesDlq.Add(1);
                return;
            }

            using var scope = _serviceProvider.CreateScope();
            var gemini = scope.ServiceProvider.GetRequiredService<IGeminiApiService>();
            var db = scope.ServiceProvider.GetRequiredService<IDatabaseConnector>();
            
            // Tronque le texte pour éviter les DoS par mémoire
            var safeDiagnostic = PrototypeGemini.Security.InputValidator.TruncateSafely(diagnostic.diagnostic_text, 10_000);
            
            string iaResponse = await gemini.GetIaGuidanceAsync(safeDiagnostic, default);
            
            if (await _featureManager.IsEnabledAsync("EnableDatabaseWrite"))
            {
                await db.UpdateDiagnosticAsync(diagnostic.id, iaResponse, default);
            }
            else
            {
                _logger.LogWarning("[DB_SKIP] Écriture BDD désactivée par Feature Flag.");
            }
        }
        
        private async Task HandlePoisonPill(ConsumeResult<Ignore, string> result, string reason, Exception? ex)
        {
            _messagesDlq.Add(1);
            await _dlqProducer.ProduceAsync(
                _kafkaSettings.DeadLetterTopic,
                result.Message.Value,
                reason,
                ex?.ToString());
            
            CommitOffset(result);
        }

        private void CommitOffset(ConsumeResult<Ignore, string> result)
        {
            if (!_kafkaSettings.EnableAutoCommit)
            {
                try { _consumer.Commit(result); }
                catch (Exception ex) { _logger.LogWarning(ex, "Échec du commit offset."); }
            }
        }
        
        private async Task CleanupCacheLoop(CancellationToken ct)
        {
            while (!ct.IsCancellationRequested)
            {
                await Task.Delay(TimeSpan.FromMinutes(10), ct);
                var cutoff = DateTime.UtcNow.AddMinutes(-30);
                var oldKeys = _recentProcessed.Where(kvp => kvp.Value < cutoff).Select(kvp => kvp.Key).ToList();
                foreach (var key in oldKeys)
                {
                    _recentProcessed.TryRemove(key, out _);
                }
                _logger.LogDebug("Nettoyage du cache de déduplication, {Count} IDs supprimés.", oldKeys.Count);
            }
        }
    }
}