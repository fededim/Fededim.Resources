using Fededim.Utilities.Extensions;
using Fededim.Utilities.Models;
using Microsoft.OpenApi.Models;
using Swashbuckle.AspNetCore.SwaggerGen;
using System;
using System.Linq;

namespace Fededim.Utilities.Api
{
    public class IgnoreSwaggerAttributeFilter : ISchemaFilter
    {
        public void Apply(OpenApiSchema model, SchemaFilterContext context)
        {

            var excludeProperties = context.Type.GetProperties().Where(prop => Attribute.IsDefined(prop, typeof(SwaggerIgnoreAttribute)));
            if (excludeProperties != null)
            {
                foreach (var property in excludeProperties)
                {
                    // Because swagger uses camel casing
                    if (model.Properties.ContainsKey(property.Name.ToCamelCase()))
                    {
                        model.Properties.Remove(property.Name);
                    }
                }
            }
        }
    }
}
