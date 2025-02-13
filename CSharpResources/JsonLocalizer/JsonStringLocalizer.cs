using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Localization;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Text.RegularExpressions;

namespace JsonLocalizer
{
    public class JsonLocalizationOptions : LocalizationOptions
    {
        public bool KeysCaseInsensitive { get; set; }
        public String EmbeddedResourcesKey { get; set; }
        public String EmbeddedResourcesAssembly { get; set; }

    }


    public class JsonStringLocalizer<T> : IStringLocalizer<T>
    {
        public Dictionary<String, String> SearchLocation { get; set; }

        // first key is culture (e.g. en, it, etc.), second key is the actual key in json files
        Dictionary<String, Dictionary<String, String>> Cache { get; set; }
        ILogger<JsonStringLocalizer<T>> Log { get; set; }

        public JsonStringLocalizer(IOptions<JsonLocalizationOptions> options, ILogger<JsonStringLocalizer<T>> log)
        {
            bool caseInsensitive = options?.Value?.KeysCaseInsensitive ?? false;

            if (caseInsensitive)
                Cache = new Dictionary<string, Dictionary<string, string>>(StringComparer.OrdinalIgnoreCase);
            else
                Cache = new Dictionary<string, Dictionary<string, string>>();

            SearchLocation = new Dictionary<string, string>();
            Log = log;

            String embeddedResourceKey = options?.Value.EmbeddedResourcesKey;

            if (!String.IsNullOrEmpty(embeddedResourceKey))
            {
                // Reads all json files
                String fname = typeof(T).Name;
                log.LogDebug($"Looking for resources with {embeddedResourceKey} for {fname}_*.json");

                var asm = Assembly.Load(options.Value.EmbeddedResourcesAssembly);

                Regex r = new Regex($"{fname}_(?<culture>[a-zA-Z\\-]+).json");

                foreach (var f in asm.GetManifestResourceNames())
                {
                    log.LogDebug($"Scanning resource {f}");

                    if (!f.StartsWith(embeddedResourceKey))
                        continue;

                    var m=r.Match(f);

                    if (!m.Success)
                        continue;

                    var cult = m.Groups["culture"].Value;

                    var config = new ConfigurationBuilder().AddJsonStream(asm.GetManifestResourceStream(f)).Build();

                    if (caseInsensitive)
                        Cache[cult] = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
                    else
                        Cache[cult] = new Dictionary<string, string>();

                    foreach (var kvp in config.AsEnumerable())
                    {
                        Cache[cult][kvp.Key] = kvp.Value;
                    }

                    SearchLocation[cult] = f;

                    log.LogInformation($"Cached JSON resource {f} culture {cult}");
                }
            }
            else
            {
                String resourcePath = !String.IsNullOrEmpty(options?.Value?.ResourcesPath) ? options?.Value?.ResourcesPath : "Resources";

                // Reads all json files
                String fname = typeof(T).Name;
                log.LogDebug($"Scanning path {resourcePath} for {fname}.*.json");

                foreach (var f in Directory.EnumerateFiles(resourcePath, $"{fname}.*.json"))
                {
                    var config = new ConfigurationBuilder().AddJsonFile(Path.GetFullPath(f), false).Build();

                    var cult = f.Substring(f.IndexOf(".") + 1, f.LastIndexOf(".") - f.IndexOf(".") - 1);

                    if (caseInsensitive)
                        Cache[cult] = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
                    else
                        Cache[cult] = new Dictionary<string, string>();

                    foreach (var kvp in config.AsEnumerable())
                    {
                        Cache[cult][kvp.Key] = kvp.Value;
                    }

                    SearchLocation[cult] = f;

                    log.LogDebug($"Cached JSON file {f}");
                }
            }
        }

        public LocalizedString this[string name]
        {
            get
            {
                var cult = CultureInfo.CurrentUICulture.Name;

                String value = null;
                if (Cache.TryGetValue(cult, out Dictionary<String, String> dict))
                    dict.TryGetValue(name, out value);
                
                if (value==null)
                    Log.LogWarning($"Unable to find key {name} in culture {cult}");

                SearchLocation.TryGetValue(cult, out String searchLoc);

                return new LocalizedString(name, value ?? name, resourceNotFound: value == null, searchedLocation: searchLoc );
            }
        }

        public LocalizedString this[string name, params object[] arguments]
        {
            get
            {
                var cult = CultureInfo.CurrentUICulture.Name;

                String format = null;
                if (Cache.TryGetValue(cult, out Dictionary<String, String> dict))
                    dict.TryGetValue(name, out format);

                if (format == null)
                    Log.LogWarning($"Unable to find key {name} in culture {cult}");

                SearchLocation.TryGetValue(cult, out String searchLoc);

                String value = String.Format(format ?? name, arguments);

                return new LocalizedString(name, value ?? name, resourceNotFound: format == null, searchedLocation: searchLoc);
            }
        }

        public IEnumerable<LocalizedString> GetAllStrings(bool includeParentCultures)
        {
            return GetAllStrings(CultureInfo.CurrentUICulture);
        }

        public IStringLocalizer WithCulture(CultureInfo culture) => this;

        private IEnumerable<LocalizedString> GetAllStrings(CultureInfo culture)
        {
            var key = culture.Name;

            if (Cache.ContainsKey(key))
            {
                foreach (var kvp in Cache[key])
                {
                    yield return new LocalizedString(kvp.Key, kvp.Value, false, SearchLocation[key]);
                }
            }
            else
            {
                yield return null;
            }
        }
    }
}
