using System;
using System.Collections.Generic;
using System.Linq;
using Microsoft.Net.Http.Headers;
using Microsoft.AspNet.OData.Builder;
using Microsoft.AspNet.OData.Extensions;
using Microsoft.AspNet.OData.Formatter;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Microsoft.OData;
using Microsoft.OData.Edm;
using Microsoft.OpenApi.Models;
//using Microsoft.OData.Edm;
using Microsoft.AspNetCore.HttpOverrides;
using System.Globalization;
using Microsoft.AspNetCore.Localization;
using JsonLocalizer;
using Swashbuckle.AspNetCore.SwaggerGen;
//using Microsoft.OData;
using Microsoft.OData.UriParser;
using System.ComponentModel;
using NetTopologySuite.Geometries;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.IdentityModel.Tokens;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNet.OData.Routing.Conventions;
using Microsoft.AspNet.OData.Formatter.Serialization;
using Microsoft.AspNet.OData.Batch;
using Serilog;
using Serilog.Events;
using Microsoft.AspNetCore.Authorization;
using Fededim.Utilities.Models.API;
using Fededim.Utilities.Models.DB;
using Fededim.Utilities.Json.NewtonsoftJson;
using Fededim.Utilities.Extensions;
using Fededim.Utilities.Models;
using Fededim.Utilities.Resources;
using Fededim.Utilities.Log.Serilog;
using Fededim.Utilities.Api.Middleware;
using Fededim.Utilities.Api.OData;

namespace Fededim.Utilities.Api
{
    public class SampleStartup
    {
        public static IConfiguration Configuration { get; private set; }
        public static SampleLocalizerService Localizer { get; set; }
        public static IHostEnvironment HostEnvironment { get; set; }
        public static ApiConfigOptions ApiOptions { get; set; }

        public SampleStartup(IConfiguration configuration, IHostEnvironment env)
        {
            Configuration = configuration;
            HostEnvironment = env;
        }

        // This method gets called by the runtime. Use this method to add services to the container.
        public void ConfigureServices(IServiceCollection services)
        {
            services.AddOData();
            services.AddODataQueryFilter();
            services.AddControllers() //(options => options.Filters.Add(typeof(LoggingActionFilter)))
                                      //.AddJsonOptions(options => options.JsonSerializerOptions.Converters.Add(new SystemTextPointJsonConverter()));  // with System.Text 
                    .AddNewtonsoftJson(x =>
                                            {
                                                x.SerializerSettings.ReferenceLoopHandling = Newtonsoft.Json.ReferenceLoopHandling.Ignore;

                                                x.SerializerSettings.Converters = GeneralExtensions.GetNewtonsoftConverters();
                                            });  // with Newtonsoft Json


            TypeDescriptor.AddAttributes(typeof(Point), new Newtonsoft.Json.JsonConverterAttribute(typeof(NewtonsoftPointJsonConverter)));

            ApiOptions = Configuration.GetSection("ConfigOptions").Get<ApiConfigOptions>();

            services.AddDbContext<SampleDBContext>();
            services.AddIdentity<User, Role>(options =>
            {
                options.SignIn.RequireConfirmedAccount = true;
                if (ApiOptions.JwtAuth.PasswordOptions != null)
                {
                    if (ApiOptions.JwtAuth.PasswordOptions.RequireDigit.HasValue)
                        options.Password.RequireDigit = ApiOptions.JwtAuth.PasswordOptions.RequireDigit.Value;
                    if (ApiOptions.JwtAuth.PasswordOptions.RequiredLength.HasValue)
                        options.Password.RequiredLength = ApiOptions.JwtAuth.PasswordOptions.RequiredLength.Value;
                    if (ApiOptions.JwtAuth.PasswordOptions.RequiredUniqueChars.HasValue)
                        options.Password.RequiredUniqueChars = ApiOptions.JwtAuth.PasswordOptions.RequiredUniqueChars.Value;
                    if (ApiOptions.JwtAuth.PasswordOptions.RequireLowercase.HasValue)
                        options.Password.RequireLowercase = ApiOptions.JwtAuth.PasswordOptions.RequireLowercase.Value;
                    if (ApiOptions.JwtAuth.PasswordOptions.RequireNonAlphanumeric.HasValue)
                        options.Password.RequireNonAlphanumeric = ApiOptions.JwtAuth.PasswordOptions.RequireNonAlphanumeric.Value;
                    if (ApiOptions.JwtAuth.PasswordOptions.RequireUppercase.HasValue)
                        options.Password.RequireUppercase = ApiOptions.JwtAuth.PasswordOptions.RequireUppercase.Value;
                }
            }).AddEntityFrameworkStores<SampleDBContext>().AddDefaultTokenProviders();

            services.AddAuthentication(opt =>
            {
                opt.DefaultAuthenticateScheme = JwtBearerDefaults.AuthenticationScheme;
                opt.DefaultChallengeScheme = JwtBearerDefaults.AuthenticationScheme;
                opt.DefaultScheme = JwtBearerDefaults.AuthenticationScheme;
            })
            .AddScheme<BasicAuthenticationHandlerOptions, BasicAuthenticationHandler>("Basic", opts => { opts.Realm = "Realm"; })
            .AddJwtBearer(options =>
            {
                options.TokenValidationParameters = new TokenValidationParameters
                {
                    ValidateIssuer = true,
                    ValidateAudience = true,
                    ValidateLifetime = true,
                    ValidateIssuerSigningKey = true,
                    ValidIssuers = ApiOptions.JwtAuth.Issuers,
                    IssuerSigningKeys = ApiOptions.JwtAuth.GetSecurityKeys(),
                    ValidAudiences = ApiOptions.JwtAuth.Audiences
                };
            });

            services.Configure<ApiConfigOptions>(Configuration.GetSection("ConfigOptions"));
            services.AddSwaggerGen(c =>
            {
                var lastMigration = SampleDBContext.CreateContext(Configuration).Database.GetMigrations().Last();
                c.SwaggerDoc("v1", new OpenApiInfo { Title = $"Sample API ({HostEnvironment.EnvironmentName} - {lastMigration})", Version = "v1" });

                c.AddSecurityDefinition("Bearer", new OpenApiSecurityScheme()
                {
                    In = ParameterLocation.Header,
                    Description = "Please insert JWT with Bearer into field",
                    Name = "Authorization",
                    Type = SecuritySchemeType.ApiKey
                });
                c.AddSecurityRequirement(new OpenApiSecurityRequirement
                {
                    { new OpenApiSecurityScheme {
                            Reference = new OpenApiReference { Type = ReferenceType.SecurityScheme, Id = "Bearer" }
                            }, new string[] { }
                    }
                });

                c.SchemaGeneratorOptions = new SchemaGeneratorOptions { SchemaIdSelector = type => type.FullName };
                c.SchemaFilter<IgnoreSwaggerAttributeFilter>();

                // Manual mapping of NetTopologySuite.Geometries.Point  otherwise Swagger loops indefinitely with PUT actions containing it, see https://github.com/domaindrivendev/Swashbuckle.AspNetCore/issues/1864
                c.MapType<Point>(() =>
                {
                    Dictionary<string, OpenApiSchema> props = new Dictionary<string, OpenApiSchema> {
                            { "X", new OpenApiSchema { Type = "number", Format = "double" } },
                            { "Y", new OpenApiSchema { Type = "number", Format = "double" } }
                        };
                    return new OpenApiSchema { Type = "object", Properties = props };
                });
                //c.MapType<Point>(() => new OpenApiSchema { Type = "string" });
            });
            services.AddSwaggerGenNewtonsoftSupport(); // explicit opt-in - needs tobe placed after AddSwaggerGen();`

            services.AddOptions();

            services.AddJsonLocalization((opt) => opt.ResourcesPath = "Resources");       // For localization

            services.AddSingleton(typeof(SampleLocalizerService));   // For localization
            services.AddScoped(typeof(ContextDbConfiguration));

            services.AddTransient<LogDbSink>();

            SetOutputFormatters(services);
        }

        // This method gets called by the runtime. Use this method to configure the HTTP request pipeline.
        public void Configure(IApplicationBuilder app, IWebHostEnvironment env, ILoggerFactory loggerFactory, SampleLocalizerService locService)
        {
            Localizer = locService;

            // For Localization
            var supportedCultures = new List<CultureInfo>
            {
                new CultureInfo("it"),
                new CultureInfo("en")
            };
            var cultureOptions = new RequestLocalizationOptions
            {
                DefaultRequestCulture = new RequestCulture("it"),
                SupportedCultures = supportedCultures,
                SupportedUICultures = supportedCultures
            };
            app.UseRequestLocalization(cultureOptions);


            if (env.IsDevelopment())
            {
                app.UseDeveloperExceptionPage();
                //app.UseWebAssemblyDebugging();  // BLAZOR CONFIG
            }


            app.UseODataBatching();
            app.UseHttpsRedirection();
            //
            // BLAZOR CONFIG
            //

            // This methods serves the WebAssembly framework files when a request is made to root path. 
            //This method also take path parameter that can be used if the WebAssembly project is only served 
            //from part of the project, giving options to combine web assembly project with a web application
            //app.UseBlazorFrameworkFiles();

            //This configuration helps in serving the static files like 
            //Javascript and CSS that is part of the Blazor WebAssembly
            //app.UseStaticFiles();

            app.UseRouting();

            app.UseAuthentication();
            app.UseAuthorization();

            app.UseForwardedHeaders(new ForwardedHeadersOptions { ForwardedHeaders = ForwardedHeaders.XForwardedFor | ForwardedHeaders.XForwardedProto });

            // Log4Net Load configuration
            //String logConfig = $"log4net.{env.EnvironmentName ?? "Development"}.config";
            //if (!File.Exists(logConfig))
            //    logConfig = "log4net.config";
            //loggerFactory.AddLog4Net(logConfig);

            // default NewtonsoftJson
            Newtonsoft.Json.JsonConvert.DefaultSettings = () => new Newtonsoft.Json.JsonSerializerSettings
            {
                ReferenceLoopHandling = Newtonsoft.Json.ReferenceLoopHandling.Ignore,
                Converters = GeneralExtensions.GetNewtonsoftConverters(),
                ContractResolver = new Newtonsoft.Json.Serialization.CamelCasePropertyNamesContractResolver()
            };

            using (var serviceScope = app.ApplicationServices.GetService<IServiceScopeFactory>().CreateScope())
            {
                // Serilog initial config must be without dbsink since the tables do not exist
                Serilog.Debugging.SelfLog.Enable(msg => System.Diagnostics.Debug.WriteLine(msg));
                Serilog.Log.Logger = new LoggerConfiguration().ReadFrom.Configuration(Configuration).CreateLogger();
                loggerFactory.AddSerilog();

                var context = serviceScope.ServiceProvider.GetRequiredService<SampleDBContext>();
                //context.Database.EnsureDeleted();
                //context.Database.EnsureCreated();

                if (ApiOptions.LogDbSink.Enabled)
                {
                    Serilog.Log.Logger = new LoggerConfiguration().ReadFrom.Configuration(Configuration)
                        .WriteTo.Sink(serviceScope.ServiceProvider.GetRequiredService<LogDbSink>(), ApiOptions.LogDbSink.MinimumLevel ?? LogEventLevel.Information)
                        .CreateLogger();
                }

                // This is needed in order to be able to read request json in ActionFilters see https://github.com/aspnet/Mvc/issues/5260
                //app.Use(next => context =>
                //{
                //    context.Request.EnableBuffering();
                //    return next(context);
                //});

                // Middlewares
                if (ApiOptions.LogApiMiddleware.Enabled)
                    app.UseMiddleware<LogApiMiddleware>();

                // Enable middleware to serve generated Swagger as a JSON endpoint.
                app.UseSwagger();

                // Enable middleware to serve swagger-ui (HTML, JS, CSS, etc.),
                // specifying the Swagger JSON endpoint.
                app.UseSwaggerUI(c =>
                {
                    c.SwaggerEndpoint("v1/swagger.json", "Sample API v1");
                    //c.DefaultModelRendering(Swashbuckle.AspNetCore.SwaggerUI.ModelRendering.Model);
                    //c.DefaultModelExpandDepth(1);
                    //c.DefaultModelsExpandDepth(1);
                });

                app.UseEndpoints(endpoints =>
                {
                    endpoints.MapControllers();
                    endpoints.EnableDependencyInjection();
                    endpoints.MaxTop(5000).SkipToken().Select().Filter().OrderBy().Expand().Count();
                    //endpoints.MapODataRoute("odata", "odata", GetEdmModel(context));

                    var handler = new TransactionalODataBatchHandler();
                    handler.MessageQuotas.MaxNestingDepth = 2;

                    endpoints.MapODataRoute("odata", "odata",
                        builder =>
                        {
                            builder.AddService(Microsoft.OData.ServiceLifetime.Singleton, typeof(IEdmModel), serviceProvider => GetEdmModel(context));
                            builder.AddService(Microsoft.OData.ServiceLifetime.Singleton, typeof(IEnumerable<IODataRoutingConvention>), serviceProvider => ODataRoutingConventions.CreateDefaultWithAttributeRouting("odata", endpoints.ServiceProvider));
                            builder.AddService(Microsoft.OData.ServiceLifetime.Singleton, typeof(ODataUriResolver), serviceProvider => new StringAsEnumResolver());
                            builder.AddService(Microsoft.OData.ServiceLifetime.Singleton, typeof(ODataSerializerProvider), serviceProvider => new DefaultODataSerializerProvider(serviceProvider));
                            builder.AddService(Microsoft.OData.ServiceLifetime.Singleton, typeof(ODataBatchHandler), serviceProvider => handler);
                        });

                    // Secure swagger UI
                    if (!env.IsDevelopment())
                    {
                        var pipeline = app.Build();
                        var basicAuthAttr = new AuthorizeAttribute { AuthenticationSchemes = "Basic" };
                        endpoints.Map("/swagger/{documentName}/swagger.json", pipeline).RequireAuthorization(basicAuthAttr);
                        endpoints.Map("/swagger/index.html", pipeline).RequireAuthorization(basicAuthAttr);
                    }

                    //
                    // BLAZOR CONFIG
                    //
                    //Add the below configuration to the end of the UseEndpoint configuration, 
                    //this will serve the index.html file from the WebAssembly when the WebAPI route 
                    //does not find a match in the routing table
                    //endpoints.MapFallbackToFile("index.html");
                });
            }



        }


        private IEdmModel GetEdmModel(SampleDBContext context)
        {
            var builder = new ODataConventionModelBuilder();

            // creates dinamically EDM Model according to context DbSet<> properties.
            foreach (var p in context.GetType().GetProperties(System.Reflection.BindingFlags.Public | System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.DeclaredOnly))
            {
                if (p.PropertyType.IsGenericType)
                {
                    var t = p.PropertyType.GetGenericTypeDefinition();

                    if (t == typeof(DbSet<>))
                        builder.AddEntitySet(p.Name, builder.AddEntityType(p.PropertyType.GetGenericArguments()[0]));

                }
            }

            // manual keys (odata bug reads only entity keys defined with a key attribute)
            builder.EntitySet<UserRefreshToken>("UserRefreshTokens").EntityType.HasKey(e => new { e.UserId, e.TokenGuid, e.RefreshToken });

            // Fix to solve serialization issues of NetTopologySuite.Geometries.Point
            builder.ComplexType<Point>().Ignore(p => p.Coordinates);
            builder.ComplexType<Point>().Ignore(p => p.Z);
            builder.ComplexType<Point>().Ignore(p => p.M);
            builder.ComplexType<Point>().Ignore(p => p.SRID);

            // removed entities (e.g. foreign key on enum types for a bug on Microsoft.OData.Client.Metadata.ClientTypeUtil.GetKeyPropertiesOnType riga 486 (https://github.com/OData/odata.net/issues/1968))
            //builder.EntityType<ent>().Ignore(c => c.enumforeignkey);

            var model = builder.GetEdmModel();

            //EdmComplexType pt=(EdmComplexType) model.FindDeclaredType(typeof(NetTopologySuite.Geometries.Point).FullName);

            return model;
        }




        private static void SetOutputFormatters(IServiceCollection services)
        {
            services.AddMvcCore(options =>
            {
                IEnumerable<ODataOutputFormatter> outputFormatters =
                    options.OutputFormatters.OfType<ODataOutputFormatter>()
                        .Where(formatter => formatter.SupportedMediaTypes.Count == 0);

                IEnumerable<ODataInputFormatter> inputFormatters =
                    options.InputFormatters.OfType<ODataInputFormatter>()
                        .Where(formatter => formatter.SupportedMediaTypes.Count == 0);

                foreach (var outputFormatter in outputFormatters)
                {
                    outputFormatter.SupportedMediaTypes.Add(new MediaTypeHeaderValue("application/odata"));
                    outputFormatter.SupportedMediaTypes.Add(new MediaTypeHeaderValue("application/json"));
                }

                foreach (var inputFormatter in inputFormatters)
                {
                    inputFormatter.SupportedMediaTypes.Add(new MediaTypeHeaderValue("application/odata"));
                    inputFormatter.SupportedMediaTypes.Add(new MediaTypeHeaderValue("application/json"));
                }
            });
        }

    }
}
