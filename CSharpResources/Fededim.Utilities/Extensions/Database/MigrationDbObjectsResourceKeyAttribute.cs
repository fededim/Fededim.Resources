using System;

namespace Fededim.Utilities.Extensions.Database
{
    [AttributeUsage(AttributeTargets.Assembly)]
    public class MigrationDbObjectsResourceKeyAttribute : Attribute
    {
        public string ResourceKey { get; private set; }
        public MigrationDbObjectsResourceKeyAttribute(string resourceKey)
        {
            ResourceKey = resourceKey;
        }
    }
}
