using Fededim.Utilities.Models.DB;
using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Threading.Tasks;

namespace Fededim.Utilities.Models.API
{
    public class DbConfiguration : Dictionary<string, string>
    {
        public T Get<T>(string key)
        {
            if (ContainsKey(key))
                return (T)Convert.ChangeType(this[key], typeof(T), CultureInfo.InvariantCulture);
            else
                return default;
        }


        public void Load(List<Configuration> configurations)
        {
            Clear();

            foreach (var conf in configurations)
                Add(conf.Key, conf.Value);
        }


        public Int32 Int32Parameter => Get<Int32>("Int32Parameter");
        public float FloatParameter => Get<float>("FloatParameter");


    }
}
