// Fichier : Services/GeminiApiService.cs
using Google.Apis.Auth.OAuth2;
using Google.Apis.GenerativeLanguage.v1beta.Data;
using Microsoft.FeatureManagement;
using System.Diagnostics.Metrics;
using System.Net.Http.Headers;
using System.Net.Http.Json; // Requis pour .PostAsJsonAsync
using System.Text.Json.Serialization;

namespace PrototypeGemini.Services
{
    public class GeminiApiService : IGeminiApiService
    {
        private readonly IMilvusService _milvusService;
        private readonly IHttpClientFactory _httpFactory;
        private readonly ILogger<GeminiApiService> _logger;
        private readonly GeminiSettings _geminiSettings;
        private readonly GoogleCloudSettings _gcSettings;
        private readonly IFeatureManager _featureManager;
        private readonly ActivitySource _activitySource = Telemetry.ActivitySource;
    private readonly Histogram<double> _geminiDuration = Telemetry.GeminiDuration;
    private readonly Counter<int> _geminiTokenUsage = Telemetry.GeminiTokenUsage;
    private string? _cachedModelId;
    private DateTimeOffset _modelCacheExpiry;
    private readonly object _modelLock = new();

        public GeminiApiService(
            IMilvusService milvusService,
            IHttpClientFactory httpFactory,
            ILogger<GeminiApiService> logger,
            IOptions<GeminiSettings> geminiOptions,
            IOptions<GoogleCloudSettings> gcOptions,
            IFeatureManager featureManager)
        {
            _milvusService = milvusService;
            _httpFactory = httpFactory;
            _logger = logger;
            _geminiSettings = geminiOptions.Value;
            _gcSettings = gcOptions.Value;
            _featureManager = featureManager;
        }

        public async Task<string> GetIaGuidanceAsync(string diagnosticText, CancellationToken cancellationToken)
        {
            if (!await _featureManager.IsEnabledAsync("EnableGeminiProcessing"))
            {
                _logger.LogWarning("[GEMINI_SKIP] Traitement Gemini désactivé par Feature Flag.");
                return "Traitement IA désactivé.";
            }

            using var activity = _activitySource.StartActivity("Gemini GetGuidance", ActivityKind.Client);
            activity?.SetTag("gen_ai.system", "google_gemini");

            var sw = Stopwatch.StartNew();
            try
            {
                // --- LOGIQUE RAG ---
                var ragContext = await _milvusService.GetContextFromDbAsync(diagnosticText, cancellationToken);
                // --- FIN LOGIQUE RAG ---

                var cleanedText = SanitizePrompt(diagnosticText);
                if (string.IsNullOrEmpty(cleanedText)) return "Aucun texte fourni.";

                var client = _httpFactory.CreateClient(HttpClientName.Gemini);

                // Essayer d'abord avec API Key (méthode simple)
                string? apiKey = Environment.GetEnvironmentVariable("GEMINI_API_KEY");
                
                string url;
                string? model;
                
                if (!string.IsNullOrEmpty(apiKey))
                {
                    // Méthode 1: API Key (Gemini API - simple et rapide)
                    _logger.LogInformation("[GEMINI_AUTH] Utilisation de l'API Key");
                    // Prefer newer models first for Gemini API (AI Studio) path style
                    var preferredGeminiApiModels = new[]
                    {
                        "models/gemini-2.5-pro",
                        "models/gemini-2.0-pro",
                        "models/gemini-1.5-pro-002",
                        "models/gemini-1.5-pro",
                        "models/gemini-1.5-flash-002",
                        "models/gemini-1.5-flash"
                    };
                    model = preferredGeminiApiModels.FirstOrDefault() ?? "models/gemini-1.5-flash";
                    url = $"{model}:generateContent?key={apiKey}";
                }
                else
                {
                    // Méthode 2: OAuth2 avec gcp-key.json (Service Account) - VERTEX AI PURE - TECHNOLOGIE DE POINTE
                    _logger.LogInformation("[VERTEX_AI] 🚀 Utilisation de VERTEX AI - Technologie de pointe avec Service Account");
                    
                    // Charger le Service Account depuis gcp-key.json
                    string gcpKeyPath = Path.Combine(Directory.GetCurrentDirectory(), "gcp-key.json");
                    
                    if (!File.Exists(gcpKeyPath))
                    {
                        _logger.LogWarning("[VERTEX_AI_SKIP] Ni GEMINI_API_KEY ni gcp-key.json trouvés.");
                        return "IA temporairement indisponible - Configuration requise.";
                    }
                    
                    // 🚀 VERTEX AI - OAUTH2 DE POINTE AVEC SCOPE CLOUD-PLATFORM COMPLET
                    Environment.SetEnvironmentVariable("GOOGLE_APPLICATION_CREDENTIALS", gcpKeyPath);
                    
                    // Utiliser GoogleCredential avec scope cloud-platform pour accès complet Vertex AI
                    var credential = GoogleCredential.GetApplicationDefault()
                        .CreateScoped("https://www.googleapis.com/auth/cloud-platform");
                    
                    // 🏆 GÉNÉRATION TOKEN OAUTH2 VERTEX AI PREMIUM
                    var token = await ((ITokenAccess)credential).GetAccessTokenForRequestAsync(
                        "https://www.googleapis.com/auth/cloud-platform", 
                        cancellationToken);
                    
                    client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", token);
                    
                    // 🚀 Utilisation de la découverte de modèle dynamique pour une robustesse maximale
                    model = await ResolveVertexAiModelIdAsync(client, token, cancellationToken);
                    url = $"https://{_gcSettings.LocationId}-aiplatform.googleapis.com/v1/projects/{_gcSettings.ProjectId}/locations/{_gcSettings.LocationId}/publishers/google/models/{model}:generateContent";
                }
                
                if (!string.IsNullOrEmpty(model))
                    activity?.SetTag("gen_ai.model", model);

                var payload = BuildRequest(cleanedText, ragContext); // Utilise le contexte RAG

                // 🔍 DEBUG: Afficher le payload exact envoyé à Vertex AI
                var debugJson = JsonSerializer.Serialize(payload, new JsonSerializerOptions { WriteIndented = true });
                _logger.LogInformation("[VERTEX_AI_DEBUG] Payload JSON envoyé:\n{JsonPayload}", debugJson);

                // Créer JsonSerializerOptions avec TypeInfoResolver pour .NET 9
                var jsonOptions = new JsonSerializerOptions
                {
                    TypeInfoResolver = new System.Text.Json.Serialization.Metadata.DefaultJsonTypeInfoResolver()
                };

                using var response = await client.PostAsJsonAsync(url, payload, jsonOptions, cancellationToken);

                if (!response.IsSuccessStatusCode)
                {
                    var errorBody = await response.Content.ReadAsStringAsync(cancellationToken);

                    // Plus de retry Vertex AI - utilisation API Gemini standard uniquement
                    _logger.LogError("[GEMINI_ERROR] Erreur API Gemini: {StatusCode} - {Error}", response.StatusCode, errorBody);

                    throw new HttpRequestException($"Échec de l'API Gemini ({response.StatusCode}): {errorBody}");
                }

                var apiResponse = await response.Content.ReadFromJsonAsync<GeminiApiResponse>(jsonOptions, cancellationToken);
                var text = apiResponse?.candidates?.FirstOrDefault()?.content?.parts?.FirstOrDefault()?.text;

                sw.Stop();
                _geminiDuration.Record(sw.Elapsed.TotalSeconds, new[] { new KeyValuePair<string, object?>("gen_ai.model", model) });

                if (apiResponse?.usageMetadata != null)
                {
                    _geminiTokenUsage.Add(apiResponse.usageMetadata.TotalTokenCount, new[] { new KeyValuePair<string, object?>("gen_ai.model", model) });
                }

                if (!string.IsNullOrEmpty(text))
                {
                    _logger.LogInformation("[VICTORY_API] Réponse de {Model} reçue en {TimeMs}ms", model, sw.ElapsedMilliseconds);
                    return text;
                }

                _logger.LogWarning("[GEMINI_WARN] {Model} a retourné une réponse vide.", model);
                return "L'IA n'a pas retourné de contenu.";
            }
            catch (OperationCanceledException)
            {
                _logger.LogWarning("[GEMINI_CANCEL] Appel Gemini annulé.");
                throw;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "[FAIL_API] Erreur fatale lors de l'appel à Gemini.");
                activity?.SetStatus(ActivityStatusCode.Error, ex.Message);
                throw;
            }
        }

        private GeminiApiRequest BuildRequest(string text, string ragContext)
        {
            // --- AMÉLIORATION 3: Optimisation des Coûts par Conscience du Modèle ---
            bool isComplex = text.Length > 200 || text.Split(' ').Length > 30;
            string modelChoiceLog = isComplex ? "complexe, utilisation du modèle de pointe" : "simple, utilisation du modèle économique";
            _logger.LogInformation("[GEMINI_COST_OPT] Diagnostic jugé {Complexity}", modelChoiceLog);

            // --- AMÉLIORATION 4: Boucle de Rétroaction sur l'Explicabilité (XAI) ---
            var prompt = new StringBuilder();
            prompt.AppendLine("Tu es un assistant médical expert. Ton analyse doit être structurée en deux parties :");
            prompt.AppendLine("1. **Recommandation :** Une recommandation claire, concise et directement exploitable.");
            prompt.AppendLine("2. **Raisonnement :** Une explication étape par étape de ton raisonnement, en te basant STRICTEMENT sur le contexte fourni et en citant les extraits pertinents.");
            prompt.AppendLine();
            prompt.Append(ragContext); // Le contexte de Milvus est injecté ici
            prompt.AppendLine();
            prompt.AppendLine("--- DIAGNOSTIC À ANALYSER ---");
            prompt.AppendLine(text);
            prompt.AppendLine("-----------------------------");

            // On ajuste la température pour un raisonnement plus factuel
            var generationConfig = _geminiSettings.GenerationConfig;
            if (!isComplex)
            {
                generationConfig.Temperature = 0.2f; // Moins de créativité pour les cas simples
            }

            return new GeminiApiRequest
            {
                contents = new List<Content> { new Content { role = "user", parts = new List<Part> { new Part { text = prompt.ToString() } } } },
                generationConfig = generationConfig
            };
        }

        /// <summary>
        /// Liste les modèles Vertex AI disponibles dans la région et sélectionne le meilleur match.
        /// Priorité: gemini-2.5-pro, gemini-2.0-pro, gemini-1.5-pro-002, gemini-1.5-pro, gemini-1.5-flash-002, gemini-1.5-flash.
        /// Résultat mis en cache 30 minutes pour éviter des appels répétés.
        /// </summary>
        private async Task<string> ResolveVertexAiModelIdAsync(HttpClient client, string accessToken, CancellationToken ct)
        {
            // Cache simple pour éviter la découverte à chaque message
            if (_cachedModelId != null && _modelCacheExpiry > DateTimeOffset.UtcNow)
            {
                return _cachedModelId;
            }

            var preferred = new[]
            {
                "gemini-2.5-pro",       // Modèle de pointe pour les cas complexes
                "gemini-2.0-pro",       // Alternative de pointe
                "gemini-1.5-pro-002",   // Modèle Pro fiable
                "gemini-1.5-pro",       // Modèle Pro standard
                "gemini-1.5-flash-002", // Modèle rapide et économique pour les cas simples
                "gemini-1.5-flash"      // Fallback économique
            };

            // 1) Tentative: lister les modèles (meilleur cas)
            try
            {
                using var req = new HttpRequestMessage(HttpMethod.Get,
                    $"https://{_gcSettings.LocationId}-aiplatform.googleapis.com/v1/projects/{_gcSettings.ProjectId}/locations/{_gcSettings.LocationId}/publishers/google/models");
                req.Headers.Authorization = new AuthenticationHeaderValue("Bearer", accessToken);
                using var resp = await client.SendAsync(req, ct);
                if (resp.IsSuccessStatusCode)
                {
                    using var stream = await resp.Content.ReadAsStreamAsync(ct);
                    using var doc = await System.Text.Json.JsonDocument.ParseAsync(stream, cancellationToken: ct);
                    if (doc.RootElement.TryGetProperty("models", out var modelsEl) && modelsEl.ValueKind == System.Text.Json.JsonValueKind.Array)
                    {
                        var available = new List<string>();
                        foreach (var m in modelsEl.EnumerateArray())
                        {
                            if (m.TryGetProperty("name", out var nameEl))
                            {
                                var full = nameEl.GetString() ?? string.Empty;
                                var idx = full.LastIndexOf('/');
                                if (idx >= 0 && idx < full.Length - 1)
                                {
                                    available.Add(full[(idx + 1)..]);
                                }
                            }
                        }

                        foreach (var p in preferred)
                        {
                            var exact = available.FirstOrDefault(a => string.Equals(a, p, StringComparison.OrdinalIgnoreCase));
                            if (exact != null) return CacheModelAndReturn(exact);

                            var starts = available.FirstOrDefault(a => a.StartsWith(p, StringComparison.OrdinalIgnoreCase));
                            if (starts != null) return CacheModelAndReturn(starts);
                        }

                        var anyGemini = available.FirstOrDefault(a => a.StartsWith("gemini", StringComparison.OrdinalIgnoreCase));
                        if (anyGemini != null) return CacheModelAndReturn(anyGemini);
                    }
                }
                else
                {
                    var body = await resp.Content.ReadAsStringAsync(ct);
                    _logger.LogWarning("[GEMINI_DISCOVERY_WARN] Echec list models ({Status}): {Body}", resp.StatusCode, body);
                }
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "[GEMINI_DISCOVERY_ERR] Impossible de lister les modèles Vertex AI");
            }

            // 2) Plan B: tester séquentiellement l'existence de chaque modèle préféré avec GET /models/{model}
            foreach (var p in preferred)
            {
                try
                {
                    using var getReq = new HttpRequestMessage(HttpMethod.Get,
                        $"https://{_gcSettings.LocationId}-aiplatform.googleapis.com/v1/projects/{_gcSettings.ProjectId}/locations/{_gcSettings.LocationId}/publishers/google/models/{p}");
                    getReq.Headers.Authorization = new AuthenticationHeaderValue("Bearer", accessToken);
                    using var getResp = await client.SendAsync(getReq, ct);
                    if (getResp.IsSuccessStatusCode)
                    {
                        return CacheModelAndReturn(p);
                    }
                    else if (getResp.StatusCode == System.Net.HttpStatusCode.NotFound)
                    {
                        // essayer des variantes: p-* (ex: gemini-2.5-pro-001)
                        // Nous ne pouvons pas deviner la sous-version sans listage; passer au modèle suivant
                        continue;
                    }
                    else
                    {
                        var body = await getResp.Content.ReadAsStringAsync(ct);
                        _logger.LogDebug("[GEMINI_DISCOVERY_INFO] GET model {Model} => {Status} {Body}", p, getResp.StatusCode, body);
                    }
                }
                catch (Exception ex)
                {
                    _logger.LogDebug(ex, "[GEMINI_DISCOVERY_INFO] Erreur pendant GET modèle {Model}", p);
                }
            }

            // 3) Ultime fallback si tout échoue
            return CacheModelAndReturn(preferred.Last());

            string CacheModelAndReturn(string id)
            {
                lock (_modelLock)
                {
                    _cachedModelId = id;
                    _modelCacheExpiry = DateTimeOffset.UtcNow.AddMinutes(30);
                    return id;
                }
            }
        }

        private string SanitizePrompt(string text)
        {
            if (string.IsNullOrWhiteSpace(text)) return "";
            var cleaned = string.Join(' ', text.Split(Array.Empty<string>(), StringSplitOptions.RemoveEmptyEntries));
            return cleaned.Length > 2000 ? cleaned.Substring(0, 2000) : cleaned;
        }
    }
}