using System;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace Fededim.Utilities.Json.SystemText
{
    public class SystemTextStringBuilderJsonConverter : JsonConverter<StringBuilder>
    {

        public override void Write(Utf8JsonWriter writer, StringBuilder p, JsonSerializerOptions options)
        {
            writer.WriteStringValue(p.ToString());
        }

        public override StringBuilder Read(ref Utf8JsonReader reader, Type type, JsonSerializerOptions options)
        {
            if (reader.TokenType != JsonTokenType.String)
            {
                throw new JsonException();
            };

            return new StringBuilder(reader.GetString());
        }

    }
}
