using Microsoft.AspNetCore.Http;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using System;
using System.Diagnostics;
using System.IO;
using System.Text.RegularExpressions;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.Data.SqlClient;
using Fededim.Utilities.Extensions;
using Fededim.Utilities.Models.API;
using Fededim.Utilities.Models.DB;
using Fededim.Utilities.Extensions.Database;

namespace Fededim.Utilities.Api.Middleware
{
    public class LogApiMiddleware
    {
        protected RequestDelegate ReqDelegate { get; }
        protected ILogger<LogApiMiddleware> Log { get; }
        protected ApiConfigOptions Opts { get; }
        protected IConfiguration Configuration { get; }
        protected string ConnectionString { get; }
        protected Regex UrlRegex { get; }

        protected int NumLogErrors;

        public LogApiMiddleware(RequestDelegate reqDelegate, ILogger<LogApiMiddleware> log, IOptions<ApiConfigOptions> opts, IConfiguration configuration)
        {
            ReqDelegate = reqDelegate;
            Log = log;
            Configuration = configuration;
            ConnectionString = Configuration.GetConnectionString("DefaultConnection") + ";Enlist=false;";
            Opts = opts?.Value;

            if (Opts?.LogApiMiddleware?.UrlRegexs?.Count > 0)
                UrlRegex = new Regex(string.Join('|', Opts.LogApiMiddleware.UrlRegexs), RegexOptions.IgnoreCase);

            // we have to create a transient context in this way because we perform asynchronous logging and 
            // when the logging thread is executed the request is already disposed and all injected
            // dependencies are unavailable because they are scoped to the request.
            //var builder = new DbContextOptionsBuilder<SampleDbContext>().UseSqlServer(ConnectionString);
            //var Ctx = new SampleDbContext(builder.Options, Configuration);
        }

        public async Task InvokeAsync(HttpContext context)
        {
            var timestamp = DateTime.Now;

            context.Request.EnableBuffering();

            // Store the original body stream for restoring the response body back to its original stream
            // Create new memory stream for reading the response; Response body streams are write-only, therefore memory stream is needed here to read
            var originalBodyStream = context.Response.Body;
            using var memoryStream = new MemoryStream();
            context.Response.Body = memoryStream;

            Stopwatch sw = Stopwatch.StartNew();
            // Call the next delegate/middleware in the pipeline
            await ReqDelegate(context);
            sw.Stop();

            var request = (await ReadRequest(context.Request)).ReplaceLineEndings();
            var response = (await ReadResponse(context.Response)).ReplaceLineEndings();

            var host = context.Connection.RemoteIpAddress.ToString();
            var method = context.Request.Method;
            var url = $"{context.Request.Scheme}://{context.Request.Host}{context.Request.Path}{context.Request.QueryString.Value}";
            var statusCode = context.Response.StatusCode;

            long? userId = null;
            if (context.User.Identity.IsAuthenticated)
            {
                var cdata = ClaimData.GetClaimData(context.User.Claims);
                userId = cdata?.Id;
            }

            // Do this last, that way you can ensure that the end results end up in the response.
            // (This resulting response may come either from the redirected route or other special routes if you have any redirection/re-execution involved in the middleware.)
            // This is very necessary. ASP.NET doesn't seem to like presenting the contents from the memory stream.
            // Therefore, the original stream provided by the ASP.NET Core engine needs to be swapped back.
            // Then write back from the previous memory stream to this original stream.
            // (The content is written in the memory stream at this point; it's just that the ASP.NET engine refuses to present the contents from the memory stream.)
            context.Response.Body = originalBodyStream;
            await memoryStream.CopyToAsync(originalBodyStream);

            if (Opts.LogApiMiddleware.UrlRegexs.Count == 0 || context.Response.StatusCode >= 400 || UrlRegex.IsMatch(context.Request.Path.ToString()))
            {
                // log asynchronously, ThreadPool.QueueUserWorkItem has less overhead than Task.Run for fire and forget scenarios
                ThreadPool.QueueUserWorkItem((args) =>
                {
                    Log.LogDebug($"Request: {method} {url} {request}");
                    Log.LogDebug($"Response: {method} {url} {statusCode} Elapsed {sw.ElapsedMilliseconds}ms: {response}");

                    var logApi = new LogApi
                    {
                        ElapsedMs = (int)sw.ElapsedMilliseconds,
                        Host = host,
                        Method = method,
                        Request = request.Truncate(4194304),
                        Response = response.Truncate(4194304),
                        Result = statusCode,
                        Timestamp = timestamp,
                        Url = url,
                        UserId = userId
                    };

                    try
                    {
                        SaveLogApi(logApi);
                    }
                    catch (Exception ex)
                    {
                        if (Interlocked.Increment(ref NumLogErrors) < 10)
                            Log.LogError(ex, "Unable to log api to database!");
                    }

                    //using (var tx=new TransactionScope(TransactionScopeOption.Suppress)) {
                    //     Ctx.LogApis.Add(new LogApi { ElapsedMs = (int) sw.ElapsedMilliseconds, Host = host, Method = method, Request = request, 
                    //         Response = response, Result = statusCode, Timestamp = timestamp, Url = url, UserId=userId });
                    //     Ctx.SaveChanges();
                    //     tx.Complete();
                    // }
                });
            }
        }

        private static async Task<string> ReadResponse(HttpResponse response)
        {
            string text;

            //We need to read the response stream from the beginning...
            response.Body.Seek(0, SeekOrigin.Begin);

            //...and copy it into a string
            using (var sr = new StreamReader(response.Body, leaveOpen: true))
                text = await sr.ReadToEndAsync();

            //We need to reset the reader for the response so that the client can read it.
            response.Body.Seek(0, SeekOrigin.Begin);

            return text;
        }


        private static async Task<string> ReadRequest(HttpRequest request)
        {
            //We need to read the request stream from the beginning...
            request.Body.Seek(0, SeekOrigin.Begin);

            using (var sr = new StreamReader(request.Body, leaveOpen: true))
                return await sr.ReadToEndAsync();
        }



        private void SaveLogApi(LogApi l)
        {
            using (var conn = new SqlConnection(ConnectionString))
                conn.ExecuteNonQuery(@$"INSERT INTO Log.LogApi (Timestamp, Host, UserId, Method, Url, Request, Result, Response, ElapsedMs)
                VALUES ({l.Timestamp}, {l.Host}, {l.UserId}, {l.Method}, {l.Url}, {l.Request.Truncate(4194304)}, {l.Result}, {l.Response.Truncate(4194304)}, {l.ElapsedMs})");

        }
    }


}
