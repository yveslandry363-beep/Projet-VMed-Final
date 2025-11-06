namespace PrototypeGemini.Validation
{
    // Helper pour associer un Setting à son Validateur
    [AttributeUsage(AttributeTargets.Class, AllowMultiple = false)]
    public class ValidateWithAttribute : Attribute
    {
        public Type ValidatorType { get; }
        public ValidateWithAttribute(Type validatorType)
        {
            ValidatorType = validatorType;
        }
    }
}