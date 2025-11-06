using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Options;

namespace PrototypeGemini.Validation
{
    // SOLUTION pour CS1061: 'IHost' does not contain 'ValidateSettings'
    public static class HostValidationExtensions
    {
        public static void ValidateSettings(this IHost host)
        {
            using var scope = host.Services.CreateScope();
            var services = scope.ServiceProvider;
            
            // Déclenche la validation en demandant chaque IOptions
            services.GetRequiredService<IOptions<KafkaSettings>>();
            services.GetRequiredService<IOptions<PostgreSqlSettings>>();
            services.GetRequiredService<IOptions<GoogleCloudSettings>>();
            services.GetRequiredService<IOptions<GeminiSettings>>();
            
            // ... (Ajoutez tous les 'settings' que vous voulez valider au démarrage) ...
        }
    }
}