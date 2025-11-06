namespace PrototypeGemini.Settings
{
    // Ce fichier corrige 'RetryPoliciesSettings' introuvable
    public class RetryPoliciesSettings
    {
        public static readonly string SectionName = "RetryPolicies";
        public RetryPolicyConfig DefaultHttp { get; set; } = new();
        public RetryPolicyConfig DefaultDatabase { get; set; } = new();
    }

    // Ce fichier corrige 'RetryPolicyConfig' introuvable
    public class RetryPolicyConfig
    {
        public int MaxAttempts { get; set; } = 3;
        public int InitialDelayMs { get; set; } = 200;
        public int MaxDelayMs { get; set; } = 5000;
    }
}