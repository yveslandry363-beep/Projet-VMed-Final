// Fichier : StartupDiagnostics.cs
using System;
using System.Diagnostics;
using System.Net.Http;
using System.Net.Sockets;
using System.Threading.Tasks;
using Npgsql;
using Confluent.Kafka;
using Serilog;

namespace PrototypeGemini.Diagnostics
{

/// <summary>
/// Classe utilitaire pour diagnostiquer et mesurer les latences de connexion au démarrage.
/// </summary>
public static class StartupDiagnostics
{
    private static readonly Stopwatch _globalStopwatch = Stopwatch.StartNew();

    /// <summary>
    /// Log le temps écoulé depuis le démarrage de l'app avec un message personnalisé.
    /// </summary>
    public static void LogCheckpoint(string message)
    {
        Log.Information("⏱️ [{Elapsed}ms] {Message}", _globalStopwatch.ElapsedMilliseconds, message);
    }

    /// <summary>
    /// Mesure la latence de connexion TCP vers un hôte et port donnés.
    /// </summary>
    public static async Task<long> MeasureTcpLatencyAsync(string host, int port, int timeoutMs = 3000)
    {
        var sw = Stopwatch.StartNew();
        try
        {
            using var client = new TcpClient();
            var connectTask = client.ConnectAsync(host, port);
            if (await Task.WhenAny(connectTask, Task.Delay(timeoutMs)) == connectTask)
            {
                await connectTask; // propagate exception if any
                sw.Stop();
                Log.Information("✅ TCP [{Host}:{Port}] connecté en {Latency}ms", host, port, sw.ElapsedMilliseconds);
                return sw.ElapsedMilliseconds;
            }
            else
            {
                Log.Warning("⏰ TCP [{Host}:{Port}] timeout après {Timeout}ms", host, port, timeoutMs);
                return -1; // timeout
            }
        }
        catch (Exception ex)
        {
            sw.Stop();
            Log.Error(ex, "❌ TCP [{Host}:{Port}] erreur après {Latency}ms", host, port, sw.ElapsedMilliseconds);
            return -1;
        }
    }

    /// <summary>
    /// Mesure la latence de connexion PostgreSQL.
    /// </summary>
    public static async Task<long> MeasurePostgreSqlLatencyAsync(string connectionString, int timeoutMs = 5000)
    {
        var sw = Stopwatch.StartNew();
        try
        {
            var builder = new NpgsqlConnectionStringBuilder(connectionString)
            {
                Timeout = timeoutMs / 1000,
                CommandTimeout = timeoutMs / 1000
            };

            await using var conn = new NpgsqlConnection(builder.ToString());
            await conn.OpenAsync();
            sw.Stop();
            Log.Information("✅ PostgreSQL connecté en {Latency}ms", sw.ElapsedMilliseconds);
            return sw.ElapsedMilliseconds;
        }
        catch (Exception ex)
        {
            sw.Stop();
            Log.Warning(ex, "⚠️ PostgreSQL erreur/timeout après {Latency}ms", sw.ElapsedMilliseconds);
            return -1;
        }
    }

    /// <summary>
    /// Mesure la latence de connexion Kafka (test producer metadata).
    /// </summary>
    public static async Task<long> MeasureKafkaLatencyAsync(string bootstrapServers, int timeoutMs = 5000)
    {
        var sw = Stopwatch.StartNew();
        try
        {
            var config = new ProducerConfig
            {
                BootstrapServers = bootstrapServers,
                SocketTimeoutMs = timeoutMs,
                RequestTimeoutMs = timeoutMs
            };

            using var producer = new ProducerBuilder<Null, Null>(config).Build();
            // Force metadata fetch
            await Task.Run(() => producer.Flush(TimeSpan.FromMilliseconds(timeoutMs)));
            sw.Stop();
            Log.Information("✅ Kafka connecté en {Latency}ms", sw.ElapsedMilliseconds);
            return sw.ElapsedMilliseconds;
        }
        catch (Exception ex)
        {
            sw.Stop();
            Log.Warning(ex, "⚠️ Kafka erreur/timeout après {Latency}ms", sw.ElapsedMilliseconds);
            return -1;
        }
    }

    /// <summary>
    /// Mesure la latence HTTP vers une URL (HEAD request).
    /// </summary>
    public static async Task<long> MeasureHttpLatencyAsync(string url, int timeoutMs = 3000)
    {
        var sw = Stopwatch.StartNew();
        try
        {
            using var client = new HttpClient { Timeout = TimeSpan.FromMilliseconds(timeoutMs) };
            var response = await client.SendAsync(new HttpRequestMessage(HttpMethod.Head, url));
            sw.Stop();
            Log.Information("✅ HTTP [{Url}] répondu en {Latency}ms (status: {StatusCode})", 
                url, sw.ElapsedMilliseconds, (int)response.StatusCode);
            return sw.ElapsedMilliseconds;
        }
        catch (Exception ex)
        {
            sw.Stop();
            Log.Warning(ex, "⚠️ HTTP [{Url}] erreur/timeout après {Latency}ms", url, sw.ElapsedMilliseconds);
            return -1;
        }
    }

    /// <summary>
    /// Réinitialise le chronomètre global (utile pour tests).
    /// </summary>
    public static void Reset()
    {
        _globalStopwatch.Restart();
    }
}
}
