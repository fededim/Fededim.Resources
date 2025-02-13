using Microsoft.IdentityModel.Tokens;
using Serilog.Events;
using System;
using System.Collections.Generic;
using System.IO;
using System.Security.Cryptography;
using System.Text.RegularExpressions;

namespace Fededim.Utilities.Models.API
{

    public class ApiEndpointOptions
    {
        public string Url { get; set; }
        public string User { get; set; }
        public string Password { get; set; }
    }


    public class OptionalPasswordOptions
    {
        public int? RequiredLength { get; set; }
        public int? RequiredUniqueChars { get; set; }
        public bool? RequireNonAlphanumeric { get; set; }
        public bool? RequireLowercase { get; set; }
        public bool? RequireUppercase { get; set; }
        public bool? RequireDigit { get; set; }
    }

    public class JwtAuthOptions
    {
        public string[] Issuers { get; set; }
        public SignKey[] SignKeys { get; set; }
        public string[] Audiences { get; set; }
        public double TokenHoursValidity { get; set; }
        public double RefreshTokenHoursValidity { get; set; }
        public OptionalPasswordOptions PasswordOptions { get; set; }

        public SecurityKey[] GetSecurityKeys()
        {
            //if (Issuers.Length != SignKeys.Length)
            //    throw new InvalidDataException($"Issers length {Issuers.Length} is not the same of SignKeys length {SignKeys.Length}!");

            var ris = new List<SecurityKey>();

            foreach (var sk in SignKeys)
            {
                if (sk.KeyType == KeyTypeEnum.Symmetric)
                    ris.Add(new SymmetricSecurityKey(Convert.FromBase64String(sk.KeyFile)));
                else
                {
                    var rsaKeys = RSA.Create();
                    if (!string.IsNullOrEmpty(sk.Password))
                        rsaKeys.ImportFromEncryptedPem(File.ReadAllText(sk.KeyFile), sk.Password);
                    else
                        rsaKeys.ImportFromPem(File.ReadAllText(sk.KeyFile));

                    ris.Add(new RsaSecurityKey(rsaKeys));
                }
            }

            return ris.ToArray();
        }
    }


    public enum KeyTypeEnum { Symmetric = 0, RSA = 1 }

    public class SignKey
    {
        public KeyTypeEnum KeyType { get; set; }
        public string KeyFile { get; set; }  // key for Symmetric, PEM filename for RSA
        public string Password { get; set; }  // optional password for PEM RSA file
    }



    public class LogFilter
    {
        public string Source { get; set; }  // it is a regex
        public LogEventLevel? MinimumLevel { get; set; }
        public Regex SourceRegex { get; set; }
    }


    public class LogDbSinkOptions
    {
        public bool Enabled { get; set; }
        public LogEventLevel? MinimumLevel { get; set; }
        public List<LogFilter> LogFilters { get; set; }

        public LogDbSinkOptions()
        {
            LogFilters = new List<LogFilter>();
        }
    }


    public class LogApiMiddlewareOptions
    {
        public bool Enabled { get; set; }
        public List<string> UrlRegexs { get; set; }

        public LogApiMiddlewareOptions()
        {
            UrlRegexs = new List<string>();
        }
    }


    public class ApiConfigOptions
    {
        public LogApiMiddlewareOptions LogApiMiddleware { get; set; }
        public LogDbSinkOptions LogDbSink { get; set; }
        public JwtAuthOptions JwtAuth { get; set; }
    }
}
