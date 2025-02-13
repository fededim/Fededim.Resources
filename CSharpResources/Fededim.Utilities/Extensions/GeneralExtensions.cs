using Fededim.Utilities.Json.NewtonsoftJson;
using NetTopologySuite.Geometries;
using Newtonsoft.Json.Converters;
using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Net;
using System.Runtime.CompilerServices;
using System.Text;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;

namespace Fededim.Utilities.Extensions
{
    public static class GeneralExtensions
    {
        public static int LevenshteinDistance(this string source, string target)
        {
            if (string.IsNullOrEmpty(source))
            {
                if (string.IsNullOrEmpty(target)) return 0;
                return target.Length;
            }
            if (string.IsNullOrEmpty(target)) return source.Length;

            if (source.Length > target.Length)
            {
                var temp = target;
                target = source;
                source = temp;
            }

            var m = target.Length;
            var n = source.Length;
            var distance = new int[2, m + 1];
            // Initialize the distance matrix
            for (var j = 1; j <= m; j++) distance[0, j] = j;

            var currentRow = 0;
            for (var i = 1; i <= n; ++i)
            {
                currentRow = i & 1;
                distance[currentRow, 0] = i;
                var previousRow = currentRow ^ 1;
                for (var j = 1; j <= m; j++)
                {
                    var cost = target[j - 1] == source[i - 1] ? 0 : 1;
                    distance[currentRow, j] = Math.Min(Math.Min(
                                distance[previousRow, j] + 1,
                                distance[currentRow, j - 1] + 1),
                                distance[previousRow, j - 1] + cost);
                }
            }
            return distance[currentRow, m];
        }

        public static object GetDefaultValue(this Type t)
        {
            if (t.IsValueType)
                return Activator.CreateInstance(t);
            else
                return null;
        }


        public static string GenerateRandomString(this int len)
        {
            Random r = new Random();
            StringBuilder sb = new StringBuilder();

            for (int i = 0; i < len; i++)
                sb.Append((char)r.Next(48, 90));

            return sb.ToString();
        }


        public static string ToString<T>(this T? val, string format, IFormatProvider provider = null) where T : struct
        {
            if (!val.HasValue)
                return string.Empty;

            var ifmt = val.Value as IFormattable;
            if (ifmt != null)
                return ifmt.ToString(format, provider);

            return val.Value.ToString();
        }

        public static string ToEncodedXmlString(this DateTime? d)
        {
            if (!d.HasValue)
                return string.Empty;
            else
                return WebUtility.UrlEncode(d.Value.ToString("o"));
        }


        public static string ToEncodedXmlString(this DateTime d)
        {
            return WebUtility.UrlEncode(d.ToString("o"));
        }

        public static string ToXmlString(this DateTime d)
        {
            return d.ToString("o");
        }


        public static string GetDateTimeFormat()
        {
            var dtf = CultureInfo.CurrentUICulture.DateTimeFormat;

            return $"{dtf.ShortDatePattern} {dtf.LongTimePattern}";
        }


        public static string GetDateTimeMSecFormat()
        {
            var dtf = CultureInfo.CurrentUICulture.DateTimeFormat;

            return $"{dtf.ShortDatePattern} {dtf.LongTimePattern}.fff";
        }


        public static string ToDatetimeString(this DateTime? d)
        {
            if (!d.HasValue)
                return string.Empty;
            else return d.Value.ToDatetimeString();
        }


        public static string ToDatetimeMSecString(this DateTime? d)
        {
            if (!d.HasValue)
                return string.Empty;
            else return d.Value.ToDatetimeMSecString();
        }

        public static string ToDatetimeString(this DateTime d)
        {
            return d.ToString(GetDateTimeFormat());
        }


        public static string ToDatetimeMSecString(this DateTime d)
        {
            return d.ToString(GetDateTimeMSecFormat());
        }


        public static string ToDatetimeString(this DateTimeOffset d)
        {
            return d.ToString(GetDateTimeFormat());
        }


        public static string ToDatetimeMSecString(this DateTimeOffset d)
        {
            return d.ToString(GetDateTimeMSecFormat());
        }


        public static string ToDatetimeString(this DateTimeOffset? d)
        {
            if (!d.HasValue)
                return string.Empty;
            else return d.Value.ToDatetimeString();
        }


        public static string ToDatetimeMSecString(this DateTimeOffset? d)
        {
            if (!d.HasValue)
                return string.Empty;
            else return d.Value.ToDatetimeMSecString();
        }



        public static string JoinString(this IEnumerable<string> list, char separator = ',', bool forDb = false)
        {
            if (list == null)
                return null;

            var sb = new StringBuilder();
            foreach (var l in list)
            {
                if (forDb)
                    sb.Append($"'{l}'{separator}");
                else
                    sb.Append($"{l}{separator}");
            }

            if (sb.Length > 0)
                sb.Length--;

            return sb.ToString();
        }


        public static string JoinString<T>(this IEnumerable<T> list, char separator = ',') where T : struct
        {
            if (list == null)
                return null;
            else return string.Join(separator.ToString(), list);
        }


        public static string JoinString<T>(this IEnumerable<Func<T>> list, char separator = ',') where T : struct
        {
            if (list == null)
                return null;

            var sb = new StringBuilder();
            foreach (var l in list)
            {
                sb.Append($"{l()}{separator}");
            }

            if (sb.Length > 0)
                sb.Length--;

            return sb.ToString();
        }


        public static string InvariantJoin<T>(IEnumerable<T> list, char separator = ',', bool querystring = false)
        {
            if (list == null)
                return string.Empty;

            var sb = new StringBuilder();
            var t = typeof(T);

            foreach (var el in list)
            {
                if (querystring && t == typeof(DateTime))
                {
                    DateTime dt = (DateTime)(object)el;
                    sb.Append($"{dt.ToString("o", CultureInfo.InvariantCulture)}{separator}");
                }
                else
                    sb.Append(FormattableString.Invariant($"{el}{separator}"));
            }

            if (sb.Length > 0)
                sb.Length--;

            return sb.ToString();
        }



        public static string ConvertCRBR(this string s)
        {
            if (s == null)
                return string.Empty;
            else
                return s.Replace("\n", "<br />");
        }


        public static string ToGeoString(this Point p)
        {
            if (p == null)
                return string.Empty;

            var NS = p.X > 0 ? "N" : "S";
            var EW = p.Y > 0 ? "E" : "W";

            return $"{Math.Abs(p.X)}{NS} {Math.Abs(p.Y)}{EW}";
        }



        public static List<Newtonsoft.Json.JsonConverter> GetNewtonsoftConverters()
        {
            return new List<Newtonsoft.Json.JsonConverter>() { new NewtonsoftPointJsonConverter(), new NewtonsoftStringBuilderJsonConverter(), new StringEnumConverter() };
        }



        public static string ToCamelCase(this string str) => string.IsNullOrEmpty(str) || str.Length < 2 ? str : char.ToLowerInvariant(str[0]) + str.Substring(1);


        public static string Truncate(this string str, int len) => str.Substring(0, Math.Min(len, str.Length));

        public static string TruncateAtFirst(this string str, params char[] ch)
        {
            int i = str.IndexOfAny(ch);
            return i < 0 ? str : str.Substring(0, i);
        }

        public static void RemoveFromEnd(this StringBuilder sb, int numChars)
        {
            if (sb.Length >= numChars)
                sb.Length = sb.Length - numChars;
        }


        public static T? ConvertToNullable<T>(this string s) where T : struct
        {
            if (string.IsNullOrEmpty(s))
                return null;

            return (T?)Convert.ChangeType(s, typeof(T));
        }


        public static T ToObject<T>(this JsonElement element)
        {
            var json = element.GetRawText();
            return JsonSerializer.Deserialize<T>(json);
        }

        public static T ToObject<T>(this JsonDocument document)
        {
            var json = document.RootElement.GetRawText();
            return JsonSerializer.Deserialize<T>(json);
        }

        public static T To<T>(this string s) where T : struct
        {
            if (string.IsNullOrWhiteSpace(s))
                return default;
            return (T)Convert.ChangeType(s, typeof(T));
        }


        public static T? ToNullable<T>(this string s) where T : struct
        {
            if (string.IsNullOrWhiteSpace(s))
                return null;
            return (T?)Convert.ChangeType(s, typeof(T));
        }

        public static T To<T>(this object o) where T : struct
        {
            if (o == DBNull.Value || o == null)
                return default;

            return (T)Convert.ChangeType(o, typeof(T));
        }


        public static T? ToNullable<T>(this object o) where T : struct
        {
            if (o == DBNull.Value || o == null)
                return null;

            return (T?)Convert.ChangeType(o, typeof(T));
        }


        public static int ToRgb(this System.Drawing.Color c)
        {
            return c.R << 16 | c.G << 8 | c.B;
        }


        public static bool IsNullOrEmpty<T>(this List<T> list)
        {
            return list == null || list.Count == 0;
        }


        public static Dictionary<TKey, List<TValue>> ToOpenDictionary<TKey, TValue>(this IQueryable<TValue> source, Func<TValue, TKey> keySelector)
        {
            var res = new Dictionary<TKey, List<TValue>>();

            foreach (var elem in source)
            {
                var key = keySelector(elem);

                if (!res.ContainsKey(key))
                    res[key] = new List<TValue>();

                res[key].Add(elem);
            }

            return res;
        }


        public static async Task<Dictionary<TKey, List<TValue>>> ToOpenDictionaryAsync<TKey, TValue>(this IQueryable<TValue> source, Func<TValue, TKey> keySelector, CancellationToken cancellationToken = default)
        {
            var res = new Dictionary<TKey, List<TValue>>();

            await foreach (var elem in ((IAsyncEnumerable<TValue>)source).WithCancellation(cancellationToken))
            {
                var key = keySelector(elem);

                if (!res.ContainsKey(key))
                    res[key] = new List<TValue>();

                res[key].Add(elem);
            }

            return res;
        }


        public static int LineNumber([CallerLineNumber] int lineNumber = 0) => lineNumber;
        public static string FileName([CallerFilePath] string filename = "") => filename;

    }
}
