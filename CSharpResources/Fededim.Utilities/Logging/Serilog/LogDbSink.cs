using Microsoft.AspNetCore.Http;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using Serilog.Core;
using Serilog.Events;
using System;
using System.Linq;
using System.Text.RegularExpressions;
using System.Threading;
using Microsoft.Data.SqlClient;
using Fededim.Utilities.Models.API;
using Fededim.Utilities.Extensions.Database;

namespace Fededim.Utilities.Log.Serilog
{
    public class LogDbSink : ILogEventSink
    {
        protected IHttpContextAccessor httpAccessor;
        protected IConfiguration configuration;

        protected string connectionString;
        protected ApiConfigOptions Opts { get; }
        protected ILogger<LogDbSink> Log { get; }

        protected int NumLogErrors;

        public LogDbSink(IServiceProvider provider)
        {
            httpAccessor = provider.GetRequiredService<IHttpContextAccessor>();
            configuration = provider.GetRequiredService<IConfiguration>();
            Opts = provider.GetRequiredService<IOptions<ApiConfigOptions>>()?.Value;
            Log = provider.GetRequiredService<ILogger<LogDbSink>>();
            connectionString = configuration.GetConnectionString("DefaultConnection") + " ;Enlist=false;";

            foreach (var f in Opts.LogDbSink.LogFilters)
                if (!string.IsNullOrEmpty(f.Source))
                    f.SourceRegex = new Regex(f.Source, RegexOptions.IgnoreCase);


            // we have to create a transient context in this way because we perform asynchronous logging and 
            // when the logging thread is executed the request is already disposed and all injected
            // dependencies are unavailable because they are scoped to the request.
            //var builder = new DbContextOptionsBuilder<SampleDbContext>().UseSqlServer(connectionString);
            //Ctx = new SampleDbContext(builder.Options, configuration);
        }

        public void Emit(LogEvent logEvent)
        {
            var source = logEvent.Properties["SourceContext"].ToString();

            if (logEvent.Level < LogEventLevel.Warning && Opts.LogDbSink.LogFilters.Count > 0)
            {
                if (!Opts.LogDbSink.LogFilters.Any(f => (f.SourceRegex == null || f.SourceRegex.IsMatch(source)) && (f.MinimumLevel == null || logEvent.Level >= f.MinimumLevel)))
                    return;
            }

            var log = new Models.DB.Log
            {
                Message = logEvent.RenderMessage(),
                Host = httpAccessor?.HttpContext?.Connection?.RemoteIpAddress?.ToString(),
                Level = logEvent.Level.ToString(),
                Source = source,
                Timestamp = logEvent.Timestamp.DateTime
            };

            if (httpAccessor?.HttpContext?.User?.Identity?.IsAuthenticated ?? false)
            {
                var cdata = ClaimData.GetClaimData(httpAccessor?.HttpContext?.User?.Claims);
                log.UserId = cdata?.Id;
            }

            //var ctx = new TravelTimeContext(new DbContextOptions<TravelTimeContext>(), configuration);

            // log asynchronously, ThreadPool.QueueUserWorkItem has less overhead than Task.Run for fire and forget scenarios
            ThreadPool.QueueUserWorkItem((arg) =>
            {
                try
                {
                    SaveLog(log);
                }
                catch (Exception ex)
                {
                    if (Interlocked.Increment(ref NumLogErrors) < 10)
                        Log.LogError(ex, "Unable to save log to database!");
                }

                //using (var tx = new TransactionScope(TransactionScopeOption.Suppress))
                //{
                //    ctx.Logs.Add(log);
                //    ctx.SaveChanges();
                //    tx.Complete();
                //}
            });
        }


        private void SaveLog(Models.DB.Log l)
        {
            using (var conn = new SqlConnection(connectionString))
                conn.ExecuteNonQuery($@"INSERT INTO Log.Log (Timestamp, Host, UserId, Source, Level, Message)
                                   VALUES ({l.Timestamp}, {l.Host}, {l.UserId}, {l.Source}, {l.Level},{l.Message})");
        }
    }
}
