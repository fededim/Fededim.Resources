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
    public class ODataControllerWithId64<T> : ODataController where T : class, IId64
    {
        protected readonly ILogger log;
        protected readonly SampleDBContext ctx;

        public ODataControllerWithId64(IServiceProvider provider, ILogger logger)
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
        public virtual async Task<T> GetByKey(long id)
        {
            var ris = await ctx.Set<T>().FindAsync(id);

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
        public virtual async Task<IActionResult> Put([FromODataUri] long key, T c)
        {
            if (!ModelState.IsValid)
                return BadRequest(ModelState);
            if (key != c.Id)
                return BadRequest();

            ctx.Set<T>().Update(c);
            await ctx.SaveChangesAsync();
            return Updated(c);
        }


        [HttpPatch]
        public virtual async Task<IActionResult> Patch([FromODataUri] long key, Delta<T> c)
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
        public virtual async Task<IActionResult> Delete([FromODataUri] long key)
        {
            await ctx.Set<T>().Where(c => c.Id == key).DeleteFromQueryAsync();
            return NoContent();
        }


        [ApiExplorerSettings(IgnoreApi = true)]
        [EnableQuery]
        public virtual SingleResult<T> Get([FromODataUri] long key)
        {
            return SingleResult.Create(ctx.Set<T>().Where(t => t.Id == key));
        }


    }
}
