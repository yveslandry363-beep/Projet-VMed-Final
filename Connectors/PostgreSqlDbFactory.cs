using Npgsql;
using System.Data;

namespace PrototypeGemini.Connectors
{
    // SOLUTION pour CS0246: 'PostgreSqlDbFactory'
    public class PostgreSqlDbFactory : IDbConnectionFactory
    {
        private readonly PostgreSqlSettings _settings;

        public PostgreSqlDbFactory(IOptions<PostgreSqlSettings> settings)
        {
            _settings = settings.Value;
        }

        public IDbConnection CreateConnection()
        {
            var builder = new NpgsqlConnectionStringBuilder(_settings.ConnectionString);
            if (_settings.UseSsl)
            {
                builder.SslMode = SslMode.Require;
            }
            return new NpgsqlConnection(builder.ConnectionString);
        }
        
        public int CommandTimeout => _settings.CommandTimeoutSeconds;
    }
}