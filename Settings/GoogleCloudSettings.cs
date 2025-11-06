namespace PrototypeGemini.Settings
{
    public class GoogleCloudSettings
    {
        public static readonly string SectionName = "GoogleCloud";
        public string ProjectId { get; set; } = string.Empty;
        public string LocationId { get; set; } = string.Empty;
        public string ServiceAccountJsonBase64 { get; set; } = string.Empty;
        public List<string> AllowedModels { get; set; } = new();
    }
}