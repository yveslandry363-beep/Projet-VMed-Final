using Confluent.Kafka;
using PrototypeGemini.Validation;

namespace PrototypeGemini.Settings
{
    [ValidateWith(typeof(KafkaSettingsValidator))]
    public class KafkaSettings
    {
        public static readonly string SectionName = "Kafka";
        
        public string BootstrapServers { get; set; } = string.Empty;
        
        // Ces lignes manquaient probablement
        public string Topic { get; set; } = string.Empty;
        public string GroupId { get; set; } = "gemini-processor-group-1";
        public string DeadLetterTopic { get; set; } = string.Empty;
        
        public string SaslUsername { get; set; } = string.Empty;
        public string SaslPassword { get; set; } = string.Empty;
        public string SslCaLocation { get; set; } = string.Empty;
        public bool EnableAutoCommit { get; set; } = false;
        public int MaxPollIntervalMs { get; set; } = 300000;
        public AutoOffsetReset AutoOffsetReset { get; set; } = AutoOffsetReset.Earliest;
    }
}