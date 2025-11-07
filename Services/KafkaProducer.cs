using Confluent.Kafka;
using PrototypeGemini.Interfaces;
using PrototypeGemini.Settings;
using System.Text;

namespace PrototypeGemini.Services
{
    public class KafkaProducer : IKafkaProducer
    {
        private readonly ILogger<KafkaProducer> _logger;
        private readonly IProducer<string, string> _producer;

        public KafkaProducer(IOptions<KafkaSettings> kafkaSettings, ILogger<KafkaProducer> logger)
        {
            _logger = logger;
            var settings = kafkaSettings.Value;
            
            // Auto-détection du mode d'authentification (même logique que ConsumerService)
            var certPath = Path.Combine(Directory.GetCurrentDirectory(), "kafka_certs", "service.cert");
            var keyPath = Path.Combine(Directory.GetCurrentDirectory(), "kafka_certs", "service.key");
            bool hasSasl = !string.IsNullOrWhiteSpace(settings.SaslUsername) && !string.IsNullOrWhiteSpace(settings.SaslPassword);
            bool hasMtls = File.Exists(certPath) && File.Exists(keyPath) && !string.IsNullOrWhiteSpace(settings.SslCaLocation);

            var config = new ProducerConfig
            {
                BootstrapServers = settings.BootstrapServers,
                ClientId = "gemini-processor-dlq-producer"
            };

            if (hasSasl)
            {
                _logger.LogInformation("[KAFKA_PRODUCER_AUTH] Mode SASL_SSL (PLAIN) détecté.");
                config.SecurityProtocol = SecurityProtocol.SaslSsl;
                config.SaslMechanism = SaslMechanism.Plain;
                config.SaslUsername = settings.SaslUsername;
                config.SaslPassword = settings.SaslPassword;
                if (!string.IsNullOrWhiteSpace(settings.SslCaLocation))
                {
                    config.SslCaLocation = settings.SslCaLocation;
                    // Désactiver la vérification de l'identité du point de terminaison pour Aiven
                    config.SslEndpointIdentificationAlgorithm = SslEndpointIdentificationAlgorithm.None;
                }
            }
            else if (hasMtls)
            {
                _logger.LogInformation("[KAFKA_PRODUCER_AUTH] Mode SSL mTLS détecté.");
                config.SecurityProtocol = SecurityProtocol.Ssl;
                config.SslCaLocation = settings.SslCaLocation;
                config.SslCertificateLocation = certPath;
                config.SslKeyLocation = keyPath;
                config.SslEndpointIdentificationAlgorithm = SslEndpointIdentificationAlgorithm.None;
            }
            else
            {
                var msg = "Aucune configuration Kafka Producer valide trouvée.";
                _logger.LogCritical(msg);
                throw new InvalidOperationException(msg);
            }

            _producer = new ProducerBuilder<string, string>(config).Build();
        }

        public async Task ProduceAsync(string topic, string message, string reason, string? exception)
        {
            try
            {
                var headers = new Headers
                {
                    { "dlq-reason", Encoding.UTF8.GetBytes(reason) },
                    { "dlq-exception", Encoding.UTF8.GetBytes(exception ?? string.Empty) }
                };

                var kafkaMessage = new Message<string, string>
                {
                    Key = $"dlq-{DateTime.UtcNow.Ticks}",
                    Value = message,
                    Headers = headers
                };

                await _producer.ProduceAsync(topic, kafkaMessage);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Ã‰chec de la production du message DLQ sur le topic {Topic}", topic);
            }
        }

        public void Dispose()
        {
            _producer.Flush(TimeSpan.FromSeconds(5));
            _producer.Dispose();
        }
    }
}
