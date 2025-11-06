using Dapper;
using Polly.Registry;
using System.Diagnostics.Metrics;

namespace PrototypeGemini.Connectors
{
    public class PostgreSqlConnector : IDatabaseConnector
    {
        // ... (Constructeur et champs, pas besoin de changer) ...
        private readonly IDbConnectionFactory _dbFactory;
        private readonly ILogger<PostgreSqlConnector> _logger;
        private readonly IAsyncPolicy _retryPolicy;
        private readonly ActivitySource _activitySource = Telemetry.ActivitySource;
        private readonly Histogram<double> _dbDuration = Telemetry.DbDuration;

        public PostgreSqlConnector(IDbConnectionFactory dbFactory, ILogger<PostgreSqlConnector> logger, IPolicyRegistry<string> policyRegistry)
        {
            _dbFactory = dbFactory;
            _logger = logger;
            _retryPolicy = policyRegistry.Get<IAsyncPolicy>(PollyPolicyName.Database);
        }


        public async Task<bool> UpdateDiagnosticAsync(int diagnosticId, string iaGuidance, CancellationToken cancellationToken)
        {
            using var activity = _activitySource.StartActivity("DB UpdateDiagnostic", ActivityKind.Client);
            activity?.SetTag("db.system", "postgresql");
            activity?.SetTag("db.statement", "UPDATE public.diagnostics");

            var sw = Stopwatch.StartNew();
            try
            {
                if (diagnosticId <= 0) throw new ArgumentOutOfRangeException(nameof(diagnosticId));
                iaGuidance ??= string.Empty;

                string sql = @"
                    UPDATE public.diagnostics 
                    SET ia_guidance = @ia_guidance, updated_at = now()
                    WHERE id = @id";

                int rows = await _retryPolicy.ExecuteAsync(async (ct) =>
                {
                    // SOLUTION (CS8417): Remplacer "await using" par "using"
                    using var conn = _dbFactory.CreateConnection();
                    
                    return await conn.ExecuteAsync(sql, new
                    {
                        ia_guidance = iaGuidance,
                        id = diagnosticId
                    }, commandTimeout: _dbFactory.CommandTimeout);
                }, cancellationToken);

                sw.Stop();
                
                // SOLUTION (CS0121): Forcer le paramètre en tableau
                _dbDuration.Record(sw.Elapsed.TotalSeconds, new[] { new KeyValuePair<string, object?>("db.operation", "update") });

                if (rows > 0)
                {
                    _logger.LogInformation("[DB_UPDATE] Mise à jour PostgreSQL OK (ID: {DiagnosticId}, Rows: {Rows}, TimeMs: {TimeMs})", diagnosticId, rows, sw.ElapsedMilliseconds);
                    return true;
                }
                else
                {
                    _logger.LogWarning("[DB_WARN] Aucune ligne affectée pour ID {DiagnosticId}. (TimeMs: {TimeMs})", diagnosticId, sw.ElapsedMilliseconds);
                    return false;
                }
            }
            catch (OperationCanceledException)
            {
                _logger.LogWarning("[DB_CANCEL] Update annulée (ID: {DiagnosticId}).", diagnosticId);
                throw;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "[FAIL_DB] Erreur fatale lors de UpdateDiagnosticAsync (ID: {DiagnosticId}).", diagnosticId);
                activity?.SetStatus(ActivityStatusCode.Error, ex.Message);
                throw;
            }
        }
    }
}