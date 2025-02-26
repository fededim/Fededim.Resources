using NetTopologySuite.Geometries;
using Newtonsoft.Json;
using System;
using System.Runtime.Serialization;

namespace Fededim.Utilities.Json.NewtonsoftJson
{
    public class NewtonsoftPointJsonConverter : JsonConverter<Point>
    {
        private readonly string X = "X";
        private readonly string Y = "Y";

        public override void WriteJson(JsonWriter writer, Point value, JsonSerializer serializer)
        {
            if (value == null)
                writer.WriteNull();
            else
            {
                writer.WriteStartObject();

                writer.WritePropertyName(X);
                writer.WriteValue(value.X);

                writer.WritePropertyName(Y);
                writer.WriteValue(value.Y);

                writer.WriteEndObject();
            }
        }

        public override Point ReadJson(JsonReader reader, Type objectType, Point existingValue, bool hasExistingValue, JsonSerializer serializer)
        {
            double x = 0, y = 0;
            string prop;
            double? value;

            if (reader.TokenType == JsonToken.Null)
                return null;
            else if (reader.TokenType != JsonToken.StartObject)
                throw new SerializationException("Invalid token, expecting start object!");

            reader.Read();
            if (reader.TokenType != JsonToken.PropertyName)
                throw new SerializationException("Invalid token, expecting property!");

            prop = (string)reader.Value;
            value = reader.ReadAsDouble();

            if (prop == X)
                x = value ?? 0;
            else if (prop == Y)
                y = value ?? 0;
            else
                throw new SerializationException($"Invalid property name, expecting {X} or {Y}");

            reader.Read();
            if (reader.TokenType != JsonToken.PropertyName)
                throw new SerializationException("Invalid token, expecting property!");

            prop = (string)reader.Value;
            value = reader.ReadAsDouble();

            if (prop == X)
                x = value ?? 0;
            else if (prop == Y)
                y = value ?? 0;
            else
                throw new SerializationException($"Invalid property name, expecting {X} or {Y}");

            reader.Read();
            if (reader.TokenType != JsonToken.EndObject)
                throw new SerializationException("Invalid token, expecting end object!");

            return new Point(new Coordinate(x, y));
        }
    }

}
