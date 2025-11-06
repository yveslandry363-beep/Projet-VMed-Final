using System.Diagnostics.Metrics;

namespace PrototypeGemini.Helpers
{
    /// <summary>
    /// Classe statique centralisant les dÃ©finitions pour OpenTelemetry (Tracing et Metrics).
    /// Permet une instrumentation personnalisÃ©e et cohÃ©rente.
    /// </summary>
    public static class Telemetry
    {
        public static readonly string ServiceName = "PrototypeGemini";
        
        // Tracing (Spans)
        public static readonly ActivitySource ActivitySource = new(ServiceName);

        // Metrics (Meters)
        public static readonly Meter Meter = new(ServiceName);

        public static readonly Counter<int> MessagesProcessed = Meter.CreateCounter<int>("app.messages.processed", "messages", "Nombre de messages Kafka traitÃ©s avec succÃ¨s.");
        public static readonly Counter<int> MessagesSkipped = Meter.CreateCounter<int>("app.messages.skipped", "messages", "Nombre de messages Kafka sautÃ©s (dÃ©dupliquÃ©s).");
        public static readonly Counter<int> MessagesDlq = Meter.CreateCounter<int>("app.messages.dlq", "messages", "Nombre de messages Kafka envoyÃ©s Ã  la DLQ.");
        
        public static readonly Histogram<double> ProcessingDuration = Meter.CreateHistogram<double>("app.processing.duration", "seconds", "DurÃ©e du traitement complet d'un message.");
        public static readonly Histogram<double> GeminiDuration = Meter.CreateHistogram<double>("app.gemini.duration", "seconds", "DurÃ©e d'un appel Ã  l'API Gemini.");
        public static readonly Counter<int> GeminiTokenUsage = Meter.CreateCounter<int>("app.gemini.tokens", "tokens", "Nombre total de tokens utilisÃ©s par Gemini.");
        public static readonly Histogram<double> DbDuration = Meter.CreateHistogram<double>("app.db.duration", "seconds", "DurÃ©e d'une requÃªte de mise Ã  jour BDD.");
    }
}
