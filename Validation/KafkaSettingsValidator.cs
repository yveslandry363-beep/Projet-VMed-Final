using FluentValidation;

namespace PrototypeGemini.Validation
{
    // SOLUTION pour CS0246: 'TValidator' (c'est un exemple)
    public class KafkaSettingsValidator : AbstractValidator<KafkaSettings>
    {
        public KafkaSettingsValidator()
        {
            RuleFor(s => s.BootstrapServers).NotEmpty();
            RuleFor(s => s.Topic).NotEmpty();
            RuleFor(s => s.GroupId).NotEmpty();
            RuleFor(s => s.DeadLetterTopic).NotEmpty();
        }
    }
}