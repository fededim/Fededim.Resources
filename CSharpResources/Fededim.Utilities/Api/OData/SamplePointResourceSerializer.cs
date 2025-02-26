using Microsoft.AspNet.OData;
using Microsoft.AspNet.OData.Formatter.Serialization;
using Microsoft.OData.Edm;
using System;
using System.Collections.Generic;
using System.Linq;

namespace Fededim.Utilities.Api.OData
{
    public class SamplePointResourceSerializer : ODataResourceSerializer
    {
        public static string[] serializableProps = new string[] { "X", "Y" };

        public SamplePointResourceSerializer(ODataSerializerProvider provider) : base(provider)
        {

        }


        public override SelectExpandNode CreateSelectExpandNode(ResourceContext resourceContext)
        {
            var selectExpandNode = base.CreateSelectExpandNode(resourceContext);

            //selectExpandNode.SelectedComplexProperties.Clear();
            selectExpandNode.SelectedComplexTypeProperties.Clear();

            List<IEdmStructuralProperty> propsToRemove = new List<IEdmStructuralProperty>();
            foreach (var n in selectExpandNode.SelectedStructuralProperties)
                if (!serializableProps.Contains(n.Name))
                    propsToRemove.Add(n);

            foreach (var p in propsToRemove)
                selectExpandNode.SelectedStructuralProperties.Remove(p);

            return selectExpandNode;
        }

    }
}
