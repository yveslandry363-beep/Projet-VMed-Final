using Confluent.Kafka;
using PrototypeGemini.Interfaces;
using PrototypeGemini.Settings;

namespace PrototypeGemini.Services
{
    public class KafkaProducer : IKafkaProducer
    {
        private readonly ILogger<KafkaProducer> _logger;
        private readonly IProducer<string, string> _producer;

        public KafkaProducer(IOptions<KafkaSettings> kafkaSettings, ILogger<KafkaProducer> logger)
        {
            _logger = logger;
            var config = new ProducerConfig
            {
                BootstrapServers = kafkaSettings.Value.BootstrapServers,
                ClientId = "gemini-processor-dlq-producer",
                SecurityProtocol = SecurityProtocol.Ssl, // Changé de SaslSsl à Ssl (mTLS uniquement)
                // SaslMechanism et SaslUsername/Password retirés car on utilise uniquement mTLS
                SslCaLocation = kafkaSettings.Value.SslCaLocation,
                SslCertificateLocation = Path.Combine(Directory.GetCurrentDirectory(), "kafka_certs", "service.cert"),
                SslKeyLocation = Path.Combine(Directory.GetCurrentDirectory(), "kafka_certs", "service.key"),
                SslEndpointIdentificationAlgorithm = SslEndpointIdentificationAlgorithm.None
            };

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
