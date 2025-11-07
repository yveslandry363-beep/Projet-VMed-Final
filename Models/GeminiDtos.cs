// Fichier: Models/GeminiDtos.cs
using System.Text.Json.Serialization;

namespace PrototypeGemini.Models
{
    // --- Requête ---

    public class GeminiApiRequest
    {
        [JsonPropertyName("contents")]
        public List<Content> contents { get; set; } = new();

        [JsonPropertyName("generationConfig")]
        public GenerationConfig generationConfig { get; set; } = new();
    }

    public class Content
    {
        [JsonPropertyName("role")]
        public string? role { get; set; }  // 🔥 VERTEX AI - RÔLE REQUIS

        [JsonPropertyName("parts")]
        public List<Part> parts { get; set; } = new();
    }

    public class Part
    {
        [JsonPropertyName("text")]
        public string text { get; set; } = string.Empty;
    }

    // --- Réponse ---

    public class GeminiApiResponse
    {
        [JsonPropertyName("candidates")]
        public List<Candidate> candidates { get; set; } = new();
        
        [JsonPropertyName("usageMetadata")]
        public UsageMetadata? usageMetadata { get; set; }
    }

    public class Candidate
    {
        [JsonPropertyName("content")]
        public Content content { get; set; } = new();
    }
    
    public class UsageMetadata
    {
        [JsonPropertyName("totalTokenCount")]
        public int TotalTokenCount { get; set; }
    }
}