using System.Text.Json.Serialization;

namespace PrototypeGemini.Settings
{
    // (J'ai ajouté la config de génération ici)
    public class GeminiSettings
    {
        public static readonly string SectionName = "Gemini";
        public string ApiBaseUrl { get; set; } = string.Empty;
        public int DefaultTimeoutSeconds { get; set; } = 60;
        public GenerationConfig GenerationConfig { get; set; } = new();
    }

    public class GenerationConfig
    {
        [JsonPropertyName("temperature")]
        public double Temperature { get; set; } = 0.4;
        
        [JsonPropertyName("topK")]
        public int TopK { get; set; } = 1;
        
        [JsonPropertyName("topP")]
        public double TopP { get; set; } = 0.9;
        
        [JsonPropertyName("maxOutputTokens")]
        public int MaxOutputTokens { get; set; } = 2048;
    }
}