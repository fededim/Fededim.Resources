using System;
using System.Collections.Generic;
using System.Net;
using System.Net.Http;
using System.Text.RegularExpressions;
using System.Threading.Tasks;
using System.Web;
using System.Linq;

namespace Fededim.Utilities
{
    /// <summary>
    /// An ADFS client exploiting ADFS WAP (Web Application Proxy) to login and retrieve the FedAuth authentication cookies
    /// </summary>
    public class ADFSCrossRestClient
    {
        protected NetworkCredential NetworkCredential { get; set; }
        protected CredentialCache CredentialCache { get; set; }
        protected CookieContainer CookieContainer { get; set; }
        protected HttpClient HttpClient { get; set; }

        // extract regexs
        protected Regex ExtractSamlTokenRegex = new Regex("name=\"wresult\" value=\"(?<samlToken>.+?)\"");
        protected Regex ExtractWctxRegex = new Regex("name=\"wctx\" value=\"(?<wctx>.+?)\"");


        /// <summary>
        /// ADFSCrossRestClient constructor
        /// </summary>
        /// <param name="baseUrl">the url of the ADFS authenticated web application or service</param>
        /// <param name="user">if user is null or empty it uses the user under which the process is run</param>
        /// <param name="password">optional, password of the user, if passed</param>
        /// <param name="timeout">maximum timeout to wait for a reply from ADFS server</param>
        public ADFSCrossRestClient(String baseUrl, String user = null, String password = null, TimeSpan? timeout = null)
        {
            var baseUri = new Uri(baseUrl);

            CookieContainer = new CookieContainer();
            CredentialCache = new CredentialCache();

            if (!String.IsNullOrEmpty(user))
                NetworkCredential = new NetworkCredential(user, password);
            else
                NetworkCredential = CredentialCache.DefaultNetworkCredentials;

            // add NTLM auth method for baseUri
            CredentialCache.Add(baseUri, "NTLM", NetworkCredential);
            //CredentialCache.Add(baseUri, "NEGOTIATE", NetworkCredential);


            HttpClient = new HttpClient(new HttpClientHandler()
            {
                PreAuthenticate = true,
                UseCookies = true,
                CookieContainer = CookieContainer,
                Credentials = CredentialCache,
                UseDefaultCredentials = String.IsNullOrEmpty(user) ? true : false
            });

            HttpClient.BaseAddress = baseUri;
            if (timeout.HasValue)
                HttpClient.Timeout = timeout.Value;

            HttpClient.DefaultRequestHeaders.Add("Accept", "*/*");
            HttpClient.DefaultRequestHeaders.Add("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36 Edg/125.0.2535.92");
        }




        /// <summary>
        /// Logins to ADFS REST service which returns a SAML token and converts it into authentication cookies.
        /// We must perform 3 calls:
        /// - an anonymous GET which retrieves the url of the api returning the token
        /// - an authenticated GET to actuallly retrieve the SAML token
        /// - an authenticated POST passing the extracted token in order to get and set the FedAuth authentication cookies in HttpClient.
        /// </summary>
        public async Task Login()
        {
            var getRootResponse = await HttpClient.GetAsync("/");

            var retrieveSamlTokenUri = getRootResponse?.RequestMessage?.RequestUri;

            if (CredentialCache.GetCredential(retrieveSamlTokenUri, "NTLM") == null)
            {
                CredentialCache.Add(retrieveSamlTokenUri, "NTLM", NetworkCredential);
                //CredentialCache.Add(retrieveSamlTokenUri, "NEGOTIATE", NetworkCredential);
            }

            var samlTokenResponse = await HttpClient.GetStringAsync(retrieveSamlTokenUri);

            var samlToken = ExtractSamlTokenRegex.Match(samlTokenResponse)?.Groups["samlToken"]?.Value;
            var wctx = ExtractWctxRegex.Match(samlTokenResponse)?.Groups["wctx"]?.Value;

            var urlEncodedDictionary = new Dictionary<string, string>
            {
                { "wctx", HttpUtility.HtmlDecode(wctx) },
                { "wa", "wsignin1.0" },
                { "wresult", HttpUtility.HtmlDecode(samlToken) }
            };

            var response = await HttpClient.PostAsync("/", new FormUrlEncodedContent(urlEncodedDictionary));

            if (!CookieContainer.GetCookies(HttpClient.BaseAddress).Cast<Cookie>().Any(c => c.Name.StartsWith("FedAuth")))
                throw new Exception($"Error logging to ADFS, response: {response}");
        }

    }
}
