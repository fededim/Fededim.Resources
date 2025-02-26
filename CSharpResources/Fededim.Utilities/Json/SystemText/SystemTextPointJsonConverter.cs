using NetTopologySuite.Geometries;
using System;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace Fededim.Utilities.Json.SystemText
{
    public class SystemTextPointJsonConverter : JsonConverter<Point>
    {
        private readonly JsonEncodedText X = JsonEncodedText.Encode("X");
        private readonly JsonEncodedText Y = JsonEncodedText.Encode("Y");

        public override Point Read(ref Utf8JsonReader reader, Type type, JsonSerializerOptions options)
        {
            if (reader.TokenType != JsonTokenType.StartObject)
            {
                throw new JsonException();
            };


            double x = default;
            bool xSet = false;

            double y = default;
            bool ySet = false;


            reader.Read();
            if (reader.TokenType != JsonTokenType.PropertyName)
            {
                throw new JsonException();
            }

            if (reader.ValueTextEquals(X.EncodedUtf8Bytes))
            {
                x = reader.GetDouble();
                xSet = true;
            }
            else if (reader.ValueTextEquals(Y.EncodedUtf8Bytes))
            {
                y = reader.GetDouble();
                ySet = true;
            }
            else
            {
                throw new JsonException();
            }

            // Get the second property.
            reader.Read();
            if (reader.TokenType != JsonTokenType.PropertyName)
            {
                throw new JsonException();
            }

            if (xSet && reader.ValueTextEquals(Y.EncodedUtf8Bytes))
            {
                y = reader.GetDouble();
            }
            else if (ySet && reader.ValueTextEquals(X.EncodedUtf8Bytes))
            {
                x = reader.GetDouble();
            }
            else
            {
                throw new JsonException();
            }

            reader.Read();

            if (reader.TokenType != JsonTokenType.EndObject)
            {
                throw new JsonException();
            }


            return new Point(x, y);
        }

        public override void Write(Utf8JsonWriter writer, Point p, JsonSerializerOptions options)
        {
            writer.WriteStringValue($"{{ lat: {p.Coordinate.X.ToString(System.Globalization.CultureInfo.InvariantCulture)}, lng: {p.Coordinate.Y.ToString(System.Globalization.CultureInfo.InvariantCulture)} }}");
        }
    }
}

