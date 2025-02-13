using Microsoft.Extensions.Localization;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using System;
using System.Reflection;

namespace JsonLocalizer
{
    public class JsonStringLocalizerFactory : IStringLocalizerFactory
    {
        public IOptions<JsonLocalizationOptions> options;
        public ILoggerFactory logFactory;

        public JsonStringLocalizerFactory(IOptions<JsonLocalizationOptions> options, ILoggerFactory logFactory)
        {
            this.options = options;
            this.logFactory = logFactory;
        }


        public IStringLocalizer Create(Type resourceSource)
        {
            var type=typeof(JsonStringLocalizer<>).MakeGenericType(resourceSource);
            var ilogtype = typeof(Logger<>).MakeGenericType(type);
            var ilog = ilogtype.GetConstructor(new Type[] { typeof(ILoggerFactory) }).Invoke(new object[] { logFactory });  //  logFactory.CreateLogger(ilogtype) does not work, does not create Logger<T> but only Logger
            var ctor = type.GetConstructor(new Type[] { typeof(IOptions<JsonLocalizationOptions>), ilogtype });

            return ((IStringLocalizer) ctor.Invoke(new object[] { options,ilog }));
        }

        public IStringLocalizer Create(string baseName, string location)
        {
            var t = Assembly.Load(new AssemblyName(location)).GetType(baseName);

            return Create(t);
        }
    }
}
