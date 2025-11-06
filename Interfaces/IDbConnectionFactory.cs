using System.Data;

namespace PrototypeGemini.Interfaces
{
    // SOLUTION pour CS0246: 'IDbConnectionFactory'
    public interface IDbConnectionFactory
    {
        IDbConnection CreateConnection();
        int CommandTimeout { get; }
    }
}
