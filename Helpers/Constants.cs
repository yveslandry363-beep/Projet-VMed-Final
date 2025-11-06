namespace PrototypeGemini.Helpers
{
    // SOLUTION pour CS0103: 'PollyPolicyName' et 'HttpClientName'
    public static class PollyPolicyName
    {
        public const string Http = "DefaultHttp";
        public const string Database = "DefaultDatabase";
    }

    public static class HttpClientName
    {
        public const string Gemini = "gemini";
    }
}