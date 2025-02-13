using Microsoft.AspNet.OData.Batch;
using Microsoft.AspNetCore.Http;
using System.Threading.Tasks;
using System.Transactions;

namespace Fededim.Utilities.Api.OData
{
    public class TransactionalODataBatchHandler : DefaultODataBatchHandler
    {
        public override async Task ProcessBatchAsync(HttpContext context, RequestDelegate nextHandler)
        {
            using (TransactionScope scope = new TransactionScope(TransactionScopeAsyncFlowOption.Enabled))
            {
                await base.ProcessBatchAsync(context, nextHandler);
                scope.Complete();
            }
        }
    }
}
