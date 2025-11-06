using System.Text.Json.Serialization;

namespace PrototypeGemini.Models
{
    /// <summary>
    /// Message Debezium SIMPLIFIÉ par ExtractNewRecordState SMT.
    /// Le payload contient directement les données (pas before/after/op).
    /// </summary>
    public class DebeziumSimplifiedMessage
    {
        [JsonPropertyName("schema")]
        public object? schema { get; set; }

        [JsonPropertyName("payload")]
        public DiagnosticPayload? payload { get; set; }
    }
    
    /// <summary>
    /// Message Debezium complet avec enveloppe 'payload'.
    /// </summary>
    public class DebeziumMessage<T> where T : class
    {
        [JsonPropertyName("schema")]
        public object? schema { get; set; }

        [JsonPropertyName("payload")]
        public DebeziumPayload<T>? payload { get; set; }
    }

    /// <summary>
    /// Structure générique pour un message Debezium (Change Data Capture).
    /// </summary>
    public class DebeziumPayload<T> where T : class
    {
        [JsonPropertyName("before")]
        public T? before { get; set; }

        [JsonPropertyName("after")]
        public T? after { get; set; }
        
        [JsonPropertyName("op")]
        public string? op { get; set; } // c=create, u=update, d=delete
        
        [JsonPropertyName("ts_ms")]
        public long? ts_ms { get; set; }
    }

    /// <summary>
    /// Représente le payload 'after' de la table 'diagnostics'.
    /// </summary>
    public class DiagnosticPayload
    {
        [JsonPropertyName("id")]
        public int id { get; set; }

        [JsonPropertyName("diagnostic_text")]
        public string diagnostic_text { get; set; } = string.Empty;
        
        [JsonPropertyName("ia_guidance")]
        public string? ia_guidance { get; set; }
        
        [JsonPropertyName("date_creation")]
        public string? date_creation { get; set; }
        
        [JsonPropertyName("created_by")]
        public string? created_by { get; set; }
        
        [JsonPropertyName("updated_at")]
        public string? updated_at { get; set; }
        
        [JsonPropertyName("__deleted")]
        public string? __deleted { get; set; }
    }
}
