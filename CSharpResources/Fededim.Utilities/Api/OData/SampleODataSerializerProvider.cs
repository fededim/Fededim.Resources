using Microsoft.AspNet.OData.Formatter.Serialization;
using Microsoft.OData.Edm;
using System;

namespace Fededim.Utilities.Api.OData
{
    public class SampleODataSerializerProvider : DefaultODataSerializerProvider
    {
        SamplePointResourceSerializer PointSerializer { get; set; }


        public SampleODataSerializerProvider(IServiceProvider rootContainer) : base(rootContainer)
        {
            PointSerializer = new SamplePointResourceSerializer(this);
        }

        public override ODataEdmTypeSerializer GetEdmTypeSerializer(IEdmTypeReference edmType)
        {
            // Support for Entity types AND Complex types
            if (edmType.FullName() == "NetTopologySuite.Geometries.Point")
            {
                return PointSerializer;
            }
            else return base.GetEdmTypeSerializer(edmType);
        }

    }
}
