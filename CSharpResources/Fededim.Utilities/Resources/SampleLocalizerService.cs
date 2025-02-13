using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Localization;
using System;

namespace Fededim.Utilities.Resources
{
    public class SampleLocalizerService
    {
        // Lists all possible localizers
        public IStringLocalizer<Strings> Strings { get; set; }

        public SampleLocalizerService(IServiceProvider provider)
        {
            Strings = provider.GetRequiredService<IStringLocalizer<Strings>>();
        }
    }
}
