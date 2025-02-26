using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Identity;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using System;
using System.Collections.Generic;
using System.IdentityModel.Tokens.Jwt;
using System.Net.Http.Headers;
using System.Security.Claims;
using System.Text;
using System.Text.Encodings.Web;
using System.Threading.Tasks;
using Fededim.Utilities.Models.DB;

namespace Fededim.Utilities.Api
{
    public class BasicAuthenticationHandlerOptions : AuthenticationSchemeOptions
    {
        public string Realm { get; set; }
    }


    public class BasicAuthenticationHandler : AuthenticationHandler<BasicAuthenticationHandlerOptions>
    {
        protected SignInManager<User> signInManager;
        protected UserManager<User> userManager;
        protected RoleManager<Role> roleManager;

        public BasicAuthenticationHandler(IOptionsMonitor<BasicAuthenticationHandlerOptions> options, ILoggerFactory logger, UrlEncoder encoder, IServiceProvider provider) : base(options, logger, encoder)
        {
            signInManager = provider.GetRequiredService<SignInManager<User>>();
            userManager = provider.GetRequiredService<UserManager<User>>();
            roleManager = provider.GetRequiredService<RoleManager<Role>>();
        }

        protected override async Task HandleChallengeAsync(AuthenticationProperties properties)
        {
            Response.Headers["WWW-Authenticate"] = $"Basic realm=\"{Options.Realm}\", charset=\"UTF-8\"";
            await base.HandleChallengeAsync(properties);
        }

        protected override async Task<AuthenticateResult> HandleAuthenticateAsync()
        {
            if (!Request.Headers.ContainsKey("Authorization"))
                return AuthenticateResult.Fail("Missing Authorization Header");

            try
            {
                var authHeader = AuthenticationHeaderValue.Parse(Request.Headers["Authorization"]);
                var credentialBytes = Convert.FromBase64String(authHeader.Parameter);
                var credentials = Encoding.UTF8.GetString(credentialBytes).Split(new[] { ':' }, 2);
                var username = credentials[0];
                var password = credentials[1];

                var res = await signInManager.PasswordSignInAsync(username, password, false, false);

                if (res.Succeeded)
                {
                    var user = await userManager.FindByNameAsync(username);
                    var sid = Guid.NewGuid().ToString();

                    var claims = new List<Claim> { new Claim(JwtRegisteredClaimNames.Sub, user.UserName), new Claim(JwtRegisteredClaimNames.Email, user.Email),
                                 new Claim(JwtRegisteredClaimNames.NameId, user.Id.ToString(),ClaimValueTypes.Integer32),
                                 new Claim(JwtRegisteredClaimNames.Jti, sid), new Claim(JwtRegisteredClaimNames.Prn,user.SecurityStamp) };

                    claims.AddRange(await userManager.GetClaimsAsync(user));  // we add user claims

                    foreach (var r in await userManager.GetRolesAsync(user))
                    {
                        var role = await roleManager.FindByNameAsync(r);
                        claims.Add(new Claim(ClaimTypes.Role, r));  // we add all user roles
                        claims.AddRange(await roleManager.GetClaimsAsync(role));  // we add all role claims
                    }

                    var identity = new ClaimsIdentity(claims, Scheme.Name);
                    var principal = new ClaimsPrincipal(identity);
                    var ticket = new AuthenticationTicket(principal, Scheme.Name);
                    return AuthenticateResult.Success(ticket);
                }
                else if (res.IsLockedOut)
                    return AuthenticateResult.Fail($"User {username} is locked out");
                else if (res.IsNotAllowed)
                    return AuthenticateResult.Fail($"User {username} is not allowed to login");
                else
                    return AuthenticateResult.Fail("Invalid username or password");
            }
            catch
            {
                return AuthenticateResult.Fail("Invalid Authorization Header");
            }
        }
    }
}
