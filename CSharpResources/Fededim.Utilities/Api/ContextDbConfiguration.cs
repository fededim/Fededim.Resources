using Fededim.Utilities.Models;
using Fededim.Utilities.Models.API;
using System.Linq;

namespace Fededim.Utilities.Api
{
    public class ContextDbConfiguration : DbConfiguration
    {
        SampleDBContext Ctx { get; set; }

        public ContextDbConfiguration(SampleDBContext context) : base()
        {
            Ctx = context;

            Reload();
        }

        public void Reload()
        {
            Load(Ctx.Configurations.ToList());
        }
    }
}
