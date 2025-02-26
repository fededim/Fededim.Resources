using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.Filters;
using Microsoft.Extensions.Logging;
using System;
using System.Diagnostics;
using System.Linq;
//using System.Text.Json;
using System.Threading.Tasks;
using Newtonsoft.Json;
using System.IO;
using Serilog.Context;

namespace Fededim.Utilities.Api.Filters
{
    public class LoggingActionFilter : ActionFilterAttribute
    {
        private readonly ILogger<LoggingActionFilter> log;
        Stopwatch sp;
        JsonSerializerSettings jss = new JsonSerializerSettings { ReferenceLoopHandling = ReferenceLoopHandling.Ignore };

        public LoggingActionFilter(ILogger<LoggingActionFilter> logger)
        {
            log = logger;
        }


        public override async Task OnActionExecutionAsync(ActionExecutingContext context, ActionExecutionDelegate next)
        {
            // assign ip for log4net logging
            //log4net.ThreadContext.Properties["ipAddress"] = context.HttpContext.Connection.RemoteIpAddress;

            // assign ip for serilog logging
            LogContext.PushProperty("ipAddress", context.HttpContext.Connection.RemoteIpAddress);

            // read body
            string reqbody = string.Empty;
            var req = context.HttpContext.Request;
            req.Body.Seek(0, SeekOrigin.Begin);
            using (var sr = new StreamReader(req.Body, leaveOpen: true))
                reqbody = (await sr.ReadToEndAsync()).Replace($"{Environment.NewLine}", "");

            // clone input parameters in order to be able to print them in case of exception
            var isExcluded = IsExcluded(context);
            context.HttpContext.Items["requestbody"] = reqbody;
            context.HttpContext.Items["isexcluded"] = isExcluded;
            //Dictionary<string, object> arguments = new Dictionary<string, object>();
            //foreach (var k in context.ActionArguments)
            //    arguments[k.Key] = k.Value;
            //context.HttpContext.Items["arguments"] = arguments;

            if (isExcluded)
                sp = Stopwatch.StartNew();
            else
            {
                log.LogDebug($"Action {context.ActionDescriptor.DisplayName} INPUTS {reqbody}");
                sp = Stopwatch.StartNew();
            }

            OnActionExecuted(await next());
        }


        public override void OnActionExecuted(ActionExecutedContext context)
        {
            var excl = (bool)context.HttpContext.Items["isexcluded"];
            if (context.Exception == null && excl)
                return;

            string outputJson = string.Empty;

            // serialize output and stop timer, by ser
            if (!context.ActionDescriptor.DisplayName.Contains("OData.MetadataController.GetMetadata"))
            {
                if (context.Result is ObjectResult)
                {
                    var or = (ObjectResult)context.Result;
                    if (or.Value is IQueryable)
                    {
                        // if the result is IQueryable we have to execute the query to get the actual time, unluckily doing this we have to take into consideration also serialization time
                        outputJson = JsonConvert.SerializeObject(or.Value, jss);
                        sp.Stop();
                    }
                    else
                    {
                        // if the result is not IQueryable we stop the time and then we serialize without taking into consideration the serialization time
                        sp.Stop();
                        outputJson = JsonConvert.SerializeObject(or.Value, jss);
                    }
                }
                else if (context.Result != null)
                {
                    sp.Stop();
                    outputJson = JsonConvert.SerializeObject(context.Result, jss);
                    // Reflection is too slow
                    //Type t = context.Result.GetType();
                    //if (t.Name == "CreatedODataResult`1" || t.Name== "UpdatedODataResult`1")
                    //{
                    //    // the result is not IQueryable so we stop the time and then we serialize without taking into consideration the serialization time
                    //    outputJson = JsonConvert.SerializeObject(t.GetProperty("Entity").GetValue(context.Result), jss);
                    //}
                }
            }

            // write a posteriori input parameters for excluded actions who have gone into exception
            if (excl)
                log.LogDebug($"Action {context.ActionDescriptor.DisplayName} INPUTS {context.HttpContext.Items["requestbody"]}");

            log.LogDebug($"Action {context.ActionDescriptor.DisplayName} ELAPSED {sp.ElapsedMilliseconds}ms OUTPUT {outputJson}");

            if (context.Exception != null)
                log.LogError(context.Exception, $"Action {context.ActionDescriptor.DisplayName} ELAPSED {sp.ElapsedMilliseconds}ms EXCEPTION");
        }


        private bool IsExcluded(ActionContext context)
        {
            var ad = context.ActionDescriptor as Microsoft.AspNetCore.Mvc.Controllers.ControllerActionDescriptor;

            if (ad != null)
            {
                return ad.ControllerTypeInfo.IsDefined(typeof(SkipLoggingActionFilterAttribute), false) || ad.MethodInfo.IsDefined(typeof(SkipLoggingActionFilterAttribute), false);
            }
            else
            {
                return false;
            }
        }
    }
}
