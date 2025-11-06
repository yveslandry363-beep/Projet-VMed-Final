// Fichier: Interfaces/IDatabaseConnector.cs

namespace PrototypeGemini.Interfaces
{
    public interface IDatabaseConnector
    {
        // SOLUTION: La signature doit avoir 3 arguments
        // pour correspondre à l'implémentation de PostgreSqlConnector
        Task<bool> UpdateDiagnosticAsync(int diagnosticId, string iaGuidance, CancellationToken cancellationToken);
    }
}