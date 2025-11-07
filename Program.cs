// Fichier : Program.cs
using System;
using System.IO;
using System.Linq;
using System.Net.Sockets;
using System.Threading.Tasks;
using System.Net.Http; 
using System.Diagnostics;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Options;
using OpenTelemetry.Metrics;
using OpenTelemetry.Resources;
using OpenTelemetry.Trace;
using OpenTelemetry.Instrumentation.Http;
using Polly;
using Polly.Extensions.Http;
using PrototypeGemini.Interfaces;
using PrototypeGemini.Diagnostics;
using Google.Apis.Auth.OAuth2;
using Google.Apis.Auth.OAuth2.Flows;
using Npgsql;
using Serilog;
using FluentValidation;
using Microsoft.Extensions.Configuration;
using PrototypeGemini.Settings;
using PrototypeGemini.Validation;
using PrototypeGemini.Connectors;
using PrototypeGemini.Helpers;
using PrototypeGemini.Services;
using Confluent.Kafka;
using Microsoft.FeatureManagement;
using System.Text; 
using Microsoft.Extensions.Diagnostics.HealthChecks; 

public partial class Program
{
    public static async Task Main(string[] args)
    {
        var startupStopwatch = Stopwatch.StartNew();
        
        // Initialisation de Serilog (étape précoce)
        Log.Logger = new LoggerConfiguration()
            .MinimumLevel.Debug()
            .WriteTo.Console()
            .CreateBootstrapLogger();

        try 
        {
            StartupDiagnostics.LogCheckpoint("🚀 Démarrage de l'application");

            // Diagnostic de latence pré-build (optionnel, mesure la connectivité)
            await RunConnectivityDiagnosticsAsync();

            StartupDiagnostics.LogCheckpoint("🏗️ Construction du Host");
            var host = CreateHostBuilder(args).Build();
            StartupDiagnostics.LogCheckpoint("✅ Host construit");

            // Déclenche la validation au démarrage (FluentValidation)
            StartupDiagnostics.LogCheckpoint("🔍 Validation des settings");
            host.ValidateSettings();
            StartupDiagnostics.LogCheckpoint("✅ Settings validés");

            startupStopwatch.Stop();
            Log.Information("⚡ Démarrage terminé en {TotalMs}ms", startupStopwatch.ElapsedMilliseconds);

            // --- AMÉLIORATION "JAMAIS VUE": EXPOSITION DE L'API ET DES WEBSOCKETS ---
            var app = host;

            // Mapper les endpoints de l'API
            app.MapPost("/validate-source", async (SourceValidationRequest request, IGeminiApiService geminiService) => {
                var prompt = $"Cet article intitulé '{request.Title}' avec le résumé '{request.Summary}' est-il crédible et pertinent pour une base de connaissances médicales ? Réponds uniquement par 'OUI' ou 'NON'.";
                var response = await geminiService.GetIaGuidanceAsync(prompt, CancellationToken.None);
                return Results.Ok(new { isCredible = response.Trim().ToUpper() == "OUI" });
            });

            // Mapper le Hub SignalR pour le streaming VR
            app.MapHub<StreamingHub>("/streamingHub");
            // --- Fin de l'amélioration ---

            await app.RunAsync();
        }
        catch (Exception ex) 
        {
            Log.Fatal(ex, "❌ Échec fatal au démarrage de l'hôte.");
        }
        finally 
        {
            Log.Information("🛑 Arrêt du Host.");
            await Log.CloseAndFlushAsync();
        }
    }

    /// <summary>
    /// Mesure les latences vers les services externes au démarrage (DB, Kafka, APIs).
    /// Exécuté en parallèle pour accélérer le diagnostic.
    /// </summary>
    private static async Task RunConnectivityDiagnosticsAsync()
    {
        StartupDiagnostics.LogCheckpoint("🔌 Diagnostic de connectivité (parallèle)");

        // Charge config minimale pour diagnostics
        var config = new ConfigurationBuilder()
            .SetBasePath(Directory.GetCurrentDirectory())
            .AddJsonFile("appsettings.json", optional: false)
            .Build();

        var tasks = new List<Task>();

        // PostgreSQL - Désactivé (hostname DNS introuvable)
        // var pgConnStr = config["PostgreSql:ConnectionString"];
        // if (!string.IsNullOrWhiteSpace(pgConnStr))
        // {
        //     tasks.Add(StartupDiagnostics.MeasurePostgreSqlLatencyAsync(pgConnStr, timeoutMs: 3000));
        // }

        // Kafka
        var kafkaBootstrap = config["Kafka:BootstrapServers"];
        if (!string.IsNullOrWhiteSpace(kafkaBootstrap))
        {
            tasks.Add(StartupDiagnostics.MeasureKafkaLatencyAsync(kafkaBootstrap, timeoutMs: 3000));
        }

        // Gemini API
        var geminiUrl = config["Gemini:ApiBaseUrl"];
        if (!string.IsNullOrWhiteSpace(geminiUrl))
        {
            tasks.Add(StartupDiagnostics.MeasureHttpLatencyAsync(geminiUrl, timeoutMs: 3000));
        }

        // OpenTelemetry Exporter - Désactivé (pas de collector local)
        // var otelEndpoint = config["OpenTelemetry:Endpoint"];
        // if (!string.IsNullOrWhiteSpace(otelEndpoint))
        // {
        //     tasks.Add(StartupDiagnostics.MeasureHttpLatencyAsync(otelEndpoint, timeoutMs: 2000));
        // }

        // Exécute tous les diagnostics en parallèle
        await Task.WhenAll(tasks);
        StartupDiagnostics.LogCheckpoint("✅ Diagnostic de connectivité terminé");
    }

    public static IHostBuilder CreateHostBuilder(string[] args) =>
        Host.CreateDefaultBuilder(args)
            // Intègre Serilog au pipeline de logging
            .UseSerilog((context, services, config) => config
                .ReadFrom.Configuration(context.Configuration)
                .ReadFrom.Services(services)
                .Enrich.FromLogContext())
            
            .ConfigureHostOptions(options =>
            {
                options.ShutdownTimeout = TimeSpan.FromSeconds(30);
            })
            
            .ConfigureServices((hostContext, services) =>
            {
                var config = hostContext.Configuration;
                
                StartupDiagnostics.LogCheckpoint("⚙️ Configuration des services");

                // Configuration et validation (avec FluentValidation)
                services.ConfigureAndValidate<PostgreSqlSettings>(config, PostgreSqlSettings.SectionName);
                services.ConfigureAndValidate<KafkaSettings>(config, KafkaSettings.SectionName);
                services.ConfigureAndValidate<GoogleCloudSettings>(config, GoogleCloudSettings.SectionName);
                services.ConfigureAndValidate<GeminiSettings>(config, GeminiSettings.SectionName);
                services.ConfigureAndValidate<RetryPoliciesSettings>(config, RetryPoliciesSettings.SectionName);

                // --- AMÉLIORATION "JAMAIS VUE": AJOUT DE SIGNALR POUR LE STREAMING TEMPS RÉEL ---
                services.AddSignalR();

                StartupDiagnostics.LogCheckpoint("📊 Configuration OpenTelemetry");
                
                // OpenTelemetry (Tracing et Metrics) - Optimisé avec timeouts
                var otelResourceBuilder = ResourceBuilder.CreateDefault()
                    .AddService(config["OpenTelemetry:ServiceName"] ?? "PrototypeGemini");

                var otelBuilder = services.AddOpenTelemetry();
                
                // Tracing
                otelBuilder.WithTracing(tracing =>
                {
                    tracing.SetResourceBuilder(otelResourceBuilder)
                        .AddNpgsql()
                        .AddSource(Telemetry.ActivitySource.Name)
                        .SetSampler(new AlwaysOnSampler());
                    
                    // Export OTLP optionnel (uniquement si endpoint configuré et accessible)
                    var otelEndpoint = config["OpenTelemetry:Endpoint"];
                    if (!string.IsNullOrWhiteSpace(otelEndpoint) && !otelEndpoint.Contains("localhost"))
                    {
                        tracing.AddOtlpExporter(opt =>
                        {
                            opt.Endpoint = new Uri(otelEndpoint);
                            opt.TimeoutMilliseconds = 2000;
                        });
                    }
                });
                
                // Metrics
                otelBuilder.WithMetrics(metrics =>
                {
                    metrics.SetResourceBuilder(otelResourceBuilder)
                        .AddRuntimeInstrumentation()
                        .AddHttpClientInstrumentation()
                        .AddMeter(Telemetry.Meter.Name);
                    
                    // Export OTLP optionnel
                    var otelEndpoint = config["OpenTelemetry:Endpoint"];
                    if (!string.IsNullOrWhiteSpace(otelEndpoint) && !otelEndpoint.Contains("localhost"))
                    {
                        metrics.AddOtlpExporter(opt =>
                        {
                            opt.Endpoint = new Uri(otelEndpoint);
                            opt.TimeoutMilliseconds = 2000;
                        });
                    }
                });

                StartupDiagnostics.LogCheckpoint("🔄 Configuration Polly (Retry Policies)");
                
                // Polly - Retry Policies (Enregistrement)
                var retrySettings = config.GetSection(RetryPoliciesSettings.SectionName).Get<RetryPoliciesSettings>()!;
                var registry = services.AddPolicyRegistry();
                registry.AddHttpRetryPolicy(PollyPolicyName.Http, retrySettings.DefaultHttp);
                registry.AddDbRetryPolicy(PollyPolicyName.Database, retrySettings.DefaultDatabase);

                StartupDiagnostics.LogCheckpoint("🌐 Configuration HttpClient");
                
                // HttpClient typé (Injection de la politique de Retry) - Optimisé
                services.AddHttpClient(HttpClientName.Gemini, client =>
                {
                    client.BaseAddress = new Uri(config.GetValue<string>("Gemini:ApiBaseUrl")!);
                    client.Timeout = TimeSpan.FromSeconds(config.GetValue<int>("Gemini:DefaultTimeoutSeconds", 30)); // Réduit de 60 à 30s
                })
                .AddPolicyHandlerFromRegistry(PollyPolicyName.Http)
                .SetHandlerLifetime(TimeSpan.FromMinutes(5)); // Réutilisation des connexions

                StartupDiagnostics.LogCheckpoint("🔧 Enregistrement des services métier");
                
                // Services du Worker
                services.AddSingleton<IDbConnectionFactory, PostgreSqlDbFactory>();
                services.AddScoped<IDatabaseConnector, PostgreSqlConnector>();
                services.AddScoped<IGeminiApiService, GeminiApiService>();
                services.AddSingleton<IMilvusService, MilvusService>(); // Ajout du service Milvus
                services.AddSingleton<IEmbeddingService, EmbeddingService>(); // Ajout du service d'embedding
                services.AddSingleton<IKafkaProducer, KafkaProducer>();

                StartupDiagnostics.LogCheckpoint(" Configuration Health Checks");
                
                // Health Checks (pour l'infrastructure) - Timeouts optimisés
                services.AddHealthChecks()
                    .AddCheck("self", () => HealthCheckResult.Healthy("OK"))
                    .AddNpgSql(config["PostgreSql:ConnectionString"]!, name: "postgresql", timeout: TimeSpan.FromSeconds(5)) // Réduit de 10 à 5s
                    .AddKafka(options =>
                    {
                        var kafkaSettings = config.GetSection(KafkaSettings.SectionName).Get<KafkaSettings>()!;
                        options.BootstrapServers = kafkaSettings.BootstrapServers;
                        options.RequestTimeoutMs = 3000; // Réduit de 5000 à 3000ms

                        if (!string.IsNullOrWhiteSpace(kafkaSettings.SaslUsername))
                        {
                            options.SecurityProtocol = SecurityProtocol.SaslSsl;
                            options.SaslMechanism = SaslMechanism.Plain;
                            options.SaslUsername = kafkaSettings.SaslUsername;
                            options.SaslPassword = kafkaSettings.SaslPassword;
                            if (!string.IsNullOrWhiteSpace(kafkaSettings.SslCaLocation))
                                options.SslCaLocation = kafkaSettings.SslCaLocation;
                        }
                    }, name: "kafka");

                StartupDiagnostics.LogCheckpoint("🚀 Enregistrement Hosted Services");
                
                // Services de sécurité avancée
                services.AddSingleton<PrototypeGemini.Security.SecureConfigurationManager>();
                services.AddSingleton<PrototypeGemini.Security.RateLimiter>();
                services.AddSingleton<PrototypeGemini.Security.CertificateValidator>();
                services.AddSingleton<PrototypeGemini.Security.AuditLogger>();
                
                // Monitoring en temps réel
                services.AddHostedService<PrototypeGemini.Monitoring.ProjectHealthMonitor>();
                
                services.AddHostedService<KafkaConsumerService>();
                services.AddFeatureManagement();
                
                StartupDiagnostics.LogCheckpoint("✅ Configuration des services terminée");
            });
}

// --- AMÉLIORATION "JAMAIS VUE": MODÈLES POUR L'API ---
public record SourceValidationRequest(string Title, string Summary);

// --- AMÉLIORATION "JAMAIS VUE": HUB POUR LE STREAMING VR/UI ---
using Microsoft.AspNetCore.SignalR;
public class StreamingHub : Hub
{
    public async Task StreamIaGuidance(string diagnosticId, string guidance)
    {
        // Pousse la recommandation à tous les clients connectés (ex: une app Unity)
        await Clients.All.SendAsync("ReceiveIaGuidance", diagnosticId, guidance);
    }
}
// Extensions pour IServiceCollection
public static class ServiceCollectionExtensions
{
    // Méthode pour configurer et valider les settings
    public static void ConfigureAndValidate<T>(this IServiceCollection services, IConfiguration config, string sectionName) where T : class
    {
        services.Configure<T>(config.GetSection(sectionName));

        var validatorType = typeof(T).GetCustomAttributes(typeof(ValidateWithAttribute), false)
                                     .Cast<ValidateWithAttribute>()
                                     .FirstOrDefault()?.ValidatorType;

        if (validatorType != null)
        {
            services.AddSingleton(validatorType);
            services.AddSingleton(typeof(IValidator<T>), validatorType);
            services.AddSingleton<IValidateOptions<T>>(sp =>
                new FluentValidationOptions<T>(sectionName, (IValidator<T>)sp.GetRequiredService(validatorType)));
        }
    }

    public static IPolicyRegistry<string> AddHttpRetryPolicy(this IPolicyRegistry<string> registry, string policyName, RetryPolicyConfig config)
    {
        var policy = HttpPolicyExtensions
            .HandleTransientHttpError()
            .Or<SocketException>()
            .WaitAndRetryAsync(config.MaxAttempts, retryAttempt =>
                TimeSpan.FromMilliseconds(Math.Min(config.InitialDelayMs * Math.Pow(2, retryAttempt - 1), config.MaxDelayMs))
            );

        registry.Add(policyName, policy);
        return registry;
    }

    public static IPolicyRegistry<string> AddDbRetryPolicy(this IPolicyRegistry<string> registry, string policyName, RetryPolicyConfig config)
    {
        var policy = Policy
            .Handle<NpgsqlException>()
            .Or<SocketException>()
            .WaitAndRetryAsync(config.MaxAttempts, retryAttempt =>
                TimeSpan.FromMilliseconds(Math.Min(config.InitialDelayMs * Math.Pow(2, retryAttempt - 1), config.MaxDelayMs))
            );

        registry.Add(policyName, policy);
        return registry;
    }
}