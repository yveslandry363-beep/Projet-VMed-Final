// Fichier: Interfaces/IGeminiApiService.cs
namespace PrototypeGemini.Interfaces
{
    public interface IGeminiApiService
    {
        Task<string> GetIaGuidanceAsync(string diagnosticText, CancellationToken cancellationToken);
    }
}