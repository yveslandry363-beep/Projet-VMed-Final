// Doit Ãªtre dans le dossier Serialization/
using PrototypeGemini.Models;
using System.Text.Json.Serialization;

namespace PrototypeGemini.Serialization
{
    /// <summary>
    /// Contexte pour le 'Source Generator' de System.Text.Json.
    /// AmÃ©liore drastiquement les performances de sÃ©rialisation/dÃ©sÃ©rialisation
    /// en Ã©vitant la rÃ©flexion au runtime.
    /// </summary>
    [JsonSourceGenerationOptions(
        // C'est la correction du bug CS0029
        PropertyNamingPolicy = JsonKnownNamingPolicy.CamelCase, 
        WriteIndented = false
    )]
    [JsonSerializable(typeof(DebeziumMessage<DiagnosticPayload>))]
    [JsonSerializable(typeof(DebeziumPayload<DiagnosticPayload>))]
    [JsonSerializable(typeof(DebeziumSimplifiedMessage))]
    [JsonSerializable(typeof(DiagnosticPayload))]
    public partial class JsonContext : JsonSerializerContext
    {
        // Les erreurs "fantÃ´mes" (CS0534, CS7036) dans ce fichier
        // disparaÃ®tront aprÃ¨s la prochaine compilation ("dotnet build"),
        // car le "Source Generator" va gÃ©nÃ©rer l'autre moitiÃ© de cette classe.
    }
}
