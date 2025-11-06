using FluentValidation;

namespace PrototypeGemini.Validation
{
    // SOLUTION pour CS0246: 'FluentValidationOptions<>'
    public class FluentValidationOptions<T> : IValidateOptions<T> where T : class
    {
        private readonly IValidator<T> _validator;
        private readonly string _name;

        public FluentValidationOptions(string name, IValidator<T> validator)
        {
            _name = name;
            _validator = validator;
        }

        public ValidateOptionsResult Validate(string? name, T options)
        {
            if (_name != null && _name != name)
                return ValidateOptionsResult.Skip;

            ArgumentNullException.ThrowIfNull(options);
            var result = _validator.Validate(options);
            
            if (result.IsValid)
                return ValidateOptionsResult.Success;

            var errors = result.Errors.Select(e => $"Validation failed for {e.PropertyName}: {e.ErrorMessage}");
            return ValidateOptionsResult.Fail(errors);
        }
    }
}