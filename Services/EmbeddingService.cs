// Fichier: Services/EmbeddingService.cs
using Google.Apis.Auth.OAuth2;
using Google.Apis.GenerativeLanguage.v1beta.Data;
using System.Net.Http.Headers;
using System.Net.Http.Json;

namespace PrototypeGemini.Services
{
    public interface IEmbeddingService
    {
        Task<IList<float>?> EmbedContentAsync(string text, CancellationToken cancellationToken);
    }

    public class EmbeddingService : IEmbeddingService
    {
        private readonly IHttpClientFactory _httpFactory;
        private readonly ILogger<EmbeddingService> _logger;
        private readonly GoogleCloudSettings _gcSettings;
        private const string EmbeddingModel = "models/text-embedding-004"; // Modèle d'embedding de pointe

        public EmbeddingService(IHttpClientFactory httpFactory, ILogger<EmbeddingService> logger, IOptions<GoogleCloudSettings> gcOptions)
        {
            _httpFactory = httpFactory;
            _logger = logger;
            _gcSettings = gcOptions.Value;
        }

        public async Task<IList<float>?> EmbedContentAsync(string text, CancellationToken cancellationToken)
        {
            try
            {
                var client = _httpFactory.CreateClient(HttpClientName.Gemini);

                // Utilisation de la même authentification OAuth2 que le service principal
                string gcpKeyPath = Path.Combine(Directory.GetCurrentDirectory(), "gcp-key.json");
                if (!File.Exists(gcpKeyPath))
                {
                    _logger.LogError("[EMBEDDING] gcp-key.json introuvable. Impossible de vectoriser.");
                    return null;
                }

                var credential = GoogleCredential.FromFile(gcpKeyPath).CreateScoped("https://www.googleapis.com/auth/cloud-platform");
                var token = await ((ITokenAccess)credential).GetAccessTokenForRequestAsync(cancellationToken: cancellationToken);
                client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", token);

                var url = $"https://{_gcSettings.LocationId}-aiplatform.googleapis.com/v1/projects/{_gcSettings.ProjectId}/locations/{_gcSettings.LocationId}/publishers/google/models/{EmbeddingModel}:predict";
                var payload = new { instances = new[] { new { content = text } } };

                var response = await client.PostAsJsonAsync(url, payload, cancellationToken);
                response.EnsureSuccessStatusCode();

                var result = await response.Content.ReadFromJsonAsync<VertexEmbeddingResponse>(cancellationToken: cancellationToken);
                return result?.Predictions?.FirstOrDefault()?.Embeddings?.Values;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "[EMBEDDING] Échec de la vectorisation du texte via Vertex AI.");
                return null;
            }
        }
    }
}