namespace PrototypeGemini.Interfaces
{
    /// <summary>
    /// Wrapper pour le Producer Kafka, permettant l'injection de dÃ©pendances et le test.
    /// SpÃ©cifiquement utilisÃ© pour la Dead Letter Queue (DLQ).
    /// </summary>
    public interface IKafkaProducer : IDisposable
    {
        Task ProduceAsync(string topic, string message, string reason, string? exception);
    }
}
