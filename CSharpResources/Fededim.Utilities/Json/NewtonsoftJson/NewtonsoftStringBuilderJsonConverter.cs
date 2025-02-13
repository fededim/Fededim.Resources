using Newtonsoft.Json;
using System;
using System.Runtime.Serialization;
using System.Text;

namespace Fededim.Utilities.Json.NewtonsoftJson
{
    public class NewtonsoftStringBuilderJsonConverter : JsonConverter<StringBuilder>
    {
        public override void WriteJson(JsonWriter writer, StringBuilder value, JsonSerializer serializer)
        {
            if (value == null)
                writer.WriteNull();
            else
                writer.WriteValue(value.ToString());
        }

        public override StringBuilder ReadJson(JsonReader reader, Type objectType, StringBuilder existingValue, bool hasExistingValue, JsonSerializer serializer)
        {
            if (reader.TokenType == JsonToken.Null)
                return null;
            else if (reader.TokenType != JsonToken.String)
                throw new SerializationException("Invalid token, expecting string!");

            return new StringBuilder(reader.Value.ToString());
        }
    }

}
