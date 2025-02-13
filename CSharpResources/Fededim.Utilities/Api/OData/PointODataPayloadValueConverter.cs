using Microsoft.OData;
using Microsoft.OData.Edm;
using NetTopologySuite.Geometries;
using Newtonsoft.Json;

namespace Fededim.Utilities.Api.OData
{
    public class LatLng
    {
        public double Lat { get; set; }
        public double Lng { get; set; }
    }

    public class PointODataPayloadValueConverter : ODataPayloadValueConverter
    {
        public override object ConvertToPayloadValue(object value, IEdmTypeReference edmTypeReference)
        {
            if (value is Point)
            {
                var p = value as Point;

                return JsonConvert.SerializeObject(new LatLng() { Lat = p.X, Lng = p.Y });
            }

            return base.ConvertToPayloadValue(value, edmTypeReference);
        }

        public override object ConvertFromPayloadValue(object value, IEdmTypeReference edmTypeReference)
        {
            if (edmTypeReference.FullName() == "NetTopologySuite.Geometries.Point" && value is string)
            {
                var latlng = JsonConvert.DeserializeObject<LatLng>((string)value);

                return new Point(latlng.Lat, latlng.Lng);
            }

            return base.ConvertFromPayloadValue(value, edmTypeReference);
        }
    }
}
