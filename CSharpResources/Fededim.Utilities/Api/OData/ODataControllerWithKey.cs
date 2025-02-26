using Fededim.Utilities.Models;
using Microsoft.AspNet.OData;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using System;
using System.Linq;
using System.Threading.Tasks;

namespace Fededim.Utilities.Api.OData
{
    public class ODataControllerWithKey<T> : ODataController where T : class, IKey
    {
        protected readonly ILogger log;
        protected readonly SampleDBContext ctx;

        public ODataControllerWithKey(IServiceProvider provider, ILogger logger)
        {
            log = logger;
            ctx = provider.GetRequiredService<SampleDBContext>();
        }

        [HttpGet]
        [EnableQuery]
        public virtual IQueryable<T> Get()
        {
            return ctx.Set<T>().AsNoTracking();
        }

        [HttpGet]
        public virtual async Task<T> GetByKey(string key)
        {
            var ris = await ctx.Set<T>().FindAsync(key);

            return ris;
        }


        // OData methods

        [HttpPost]
        public virtual async Task<IActionResult> Post([FromBody] T c)
        {
            if (!ModelState.IsValid)
                return BadRequest(ModelState);

            ctx.Set<T>().Add(c);
            await ctx.SaveChangesAsync();
            return Created(c);
        }



        [HttpPut]
        public virtual async Task<IActionResult> Put([FromODataUri] string key, T c)
        {
            if (!ModelState.IsValid)
                return BadRequest(ModelState);
            if (key != c.Key)
                return BadRequest();

            ctx.Set<T>().Update(c);
            await ctx.SaveChangesAsync();
            return Updated(c);
        }


        [HttpPatch]
        public virtual async Task<IActionResult> Patch([FromODataUri] string key, Delta<T> c)
        {
            if (!ModelState.IsValid)
                return BadRequest(ModelState);

            var entity = await ctx.Set<T>().FindAsync(key);
            if (entity == null)
                return NotFound();

            c.Patch(entity);
            await ctx.SaveChangesAsync();
            return Updated(entity);
        }




        [HttpDelete]
        public virtual async Task<IActionResult> Delete([FromODataUri] string key)
        {
            await ctx.Set<T>().Where(c => c.Key == key).DeleteFromQueryAsync();
            return NoContent();
        }


        [ApiExplorerSettings(IgnoreApi = true)]
        [EnableQuery]
        public virtual SingleResult<T> Get([FromODataUri] string key)
        {
            return SingleResult.Create(ctx.Set<T>().Where(t => t.Key == key));
        }


    }
}
