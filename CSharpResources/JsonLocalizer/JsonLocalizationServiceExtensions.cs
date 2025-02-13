using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Localization;
using System;

namespace JsonLocalizer
{
    public static class JsonLocalizationServiceExtensions
    {
        public static IServiceCollection AddJsonLocalization(this IServiceCollection services)
        {
            if (services == null)
                throw new ArgumentNullException(nameof(services));

            AddServices(services);

            return services;
        }


        public static IServiceCollection AddJsonLocalization(this IServiceCollection services, Action<JsonLocalizationOptions> options)
        {
            if (services == null)
                throw new ArgumentNullException(nameof(services));

            if (options == null)
                throw new ArgumentNullException(nameof(options));

            AddServices(services);
            services.Configure<JsonLocalizationOptions>(options);

            return services;
        }

        private static void AddServices(IServiceCollection services)
        {
            services.AddSingleton(typeof(IStringLocalizerFactory), typeof(JsonLocalizer.JsonStringLocalizerFactory));
            services.AddSingleton(typeof(IStringLocalizer<>), typeof(JsonLocalizer.JsonStringLocalizer<>));    // For localization
            //services.AddSingleton(typeof(IHtmlLocalizer<>), typeof(JsonLocalizer.JsonHtmlLocalizer<>));    // For localization
        }
    }
}
