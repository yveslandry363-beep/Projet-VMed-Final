// Fichier: Services/MilvusService.cs
using Grpc.Net.Client;
using Milvus.Client;
using Google.Apis.GenerativeLanguage.v1beta.Data;

namespace PrototypeGemini.Services
{
    public interface IMilvusService
    {
        Task<string> GetContextFromDbAsync(string query, CancellationToken cancellationToken);
    }

    public class MilvusService : IMilvusService
    {
        private readonly MilvusClient _client;
        private readonly IEmbeddingService _embeddingService;
        private readonly ILogger<MilvusService> _logger;
        private const string CollectionName = "medical_knowledge_base";
        private bool _isMilvusAvailable = true;
        private DateTime _lastCheckTime = DateTime.MinValue;

        public MilvusService(ILogger<MilvusService> logger, IEmbeddingService embeddingService)
        {
            _logger = logger;
            _embeddingService = embeddingService;
            
            // --- AMÉLIORATION 1: Auto-Guérison (Self-Healing) ---
            // On ne se connecte pas immédiatement. La connexion sera tentée à la première requête.
            // Cela évite un plantage au démarrage si Milvus n'est pas prêt.
            // Configuration du client Milvus
            var channel = GrpcChannel.ForAddress("http://localhost:19530");
            _client = new MilvusClient(channel);
        }

        public async Task<string> GetContextFromDbAsync(string query, CancellationToken cancellationToken)
        {
            try
            {
                // --- AMÉLIORATION 1: Auto-Guérison (Self-Healing) ---
                if (!_isMilvusAvailable && DateTime.UtcNow - _lastCheckTime < TimeSpan.FromMinutes(1))
                {
                    // Si Milvus est connu pour être indisponible, on ne réessaie pas pendant 1 minute.
                    return string.Empty;
                }
                _lastCheckTime = DateTime.UtcNow;
                // --- Fin de l'amélioration ---

                _logger.LogInformation("[RAG_MILVUS] Interrogation de Milvus pour la requête: '{Query}'", query);

                // 1. Vectoriser la requête utilisateur avec le même modèle d'embedding
                var queryVector = await _embeddingService.EmbedContentAsync(query, cancellationToken);
                if (queryVector == null || !queryVector.Any())
                {
                    _logger.LogWarning("[RAG_MILVUS] Impossible de vectoriser la requête.");
                    return string.Empty;
                }

                // 2. Exécuter la recherche de similarité dans Milvus
                var searchParameters = new SearchParameters(CollectionName, new[] { queryVector })
                {
                    TopK = 5,
                    OutputFields = { "text", "source" } // Assumant que 'text' et 'source' sont stockés
                };
                
                var results = await _client.SearchAsync(searchParameters, cancellationToken);

                // 3. Concaténer les résultats pour former le contexte
                var contextBuilder = new StringBuilder();
                contextBuilder.AppendLine("--- CONTEXTE DE LA BASE DE CONNAISSANCES ---");
                foreach (var result in results.Results.Hits)
                {
                    var textField = result.Fields.FirstOrDefault(f => f.FieldCase == Milvus.Client.Field.FieldOneofCase.ScalarField && f.ScalarField.DataCase == Milvus.Client.ScalarField.DataOneofCase.StringData);
                    if (textField != null)
                    {
                        contextBuilder.AppendLine($"- {textField.ScalarField.StringData.Data.FirstOrDefault()}");
                    }
                }
                contextBuilder.AppendLine("-----------------------------------------");
                
                _logger.LogInformation("[RAG_MILVUS] Contexte de {Count} documents récupéré.", results.Results.Hits.Count);
                return contextBuilder.ToString();
            }
            catch (Exception ex)
            {
                // --- AMÉLIORATION 1: Auto-Guérison (Self-Healing) ---
                _logger.LogError(ex, "[RAG_SELF_HEAL] Échec de la recherche dans Milvus. Le mode RAG est temporairement désactivé.");
                _isMilvusAvailable = false; // On marque Milvus comme indisponible.
                return string.Empty; // En cas d'erreur, on continue sans contexte RAG
            }
        }
    }
}