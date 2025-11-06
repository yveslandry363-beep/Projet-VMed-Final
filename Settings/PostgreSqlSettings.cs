namespace PrototypeGemini.Settings
{
    public class PostgreSqlSettings
    {
        public static readonly string SectionName = "PostgreSql";
        
        // Ces lignes manquaient probablement
        public string ConnectionString { get; set; } = string.Empty;
        public int CommandTimeoutSeconds { get; set; } = 30;
        public bool UseSsl { get; set; } = true;
    }
}