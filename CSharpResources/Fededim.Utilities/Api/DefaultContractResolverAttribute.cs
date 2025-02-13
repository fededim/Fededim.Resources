using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.Filters;
using Newtonsoft.Json;
using Newtonsoft.Json.Serialization;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Mvc.Formatters;
using System.Buffers;
using Microsoft.Extensions.DependencyInjection;

namespace Fededim.Utilities.Api
{
    public class DefaultContractResolverAttribute : ActionFilterAttribute
    {
        public override void OnResultExecuting(ResultExecutingContext context)
        {
            if (context.Result is ObjectResult objectResult)
            {
                var serializerSettings = new JsonSerializerSettings { ContractResolver = new DefaultContractResolver() };
                var mvcOptions = new MvcOptions { };
                var arrayPool = context.HttpContext.RequestServices.GetRequiredService<ArrayPool<char>>();

                var jsonFormatter = new NewtonsoftJsonOutputFormatter(serializerSettings, arrayPool, mvcOptions);
                objectResult.Formatters.Add(jsonFormatter);
            }

            base.OnResultExecuting(context);
        }
    }
}
