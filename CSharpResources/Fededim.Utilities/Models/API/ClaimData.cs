using System;
using System.Collections.Generic;
using System.IdentityModel.Tokens.Jwt;
using System.Linq;
using System.Security.Claims;
using System.Text;
using System.Threading.Tasks;

namespace Fededim.Utilities.Models.API
{
    public class ClaimData
    {
        public long Id { get; set; }
        public string UserName { get; set; }
        public string Email { get; set; }
        public string Jti { get; set; }
        public string Prn { get; set; }

        public static ClaimData GetClaimData(ClaimsPrincipal user)
        {
            return GetClaimData(user?.Claims);
        }


        public static ClaimData GetClaimData(IEnumerable<Claim> claims)
        {
            if (claims == null)
                return null;

            var ris = new ClaimData();

            // Don't know why but the claims contained in ClaimsPrincipal are different from the claims inside token, asp net converts them somehow
            // For example both sub and nameid are mapped to ClaimTypes.NameIdentifier 
            foreach (var c in claims)
            {
                switch (c.Type)
                {
                    case ClaimTypes.Name:
                    case JwtRegisteredClaimNames.Sub:
                        ris.UserName = c.Value;
                        break;

                    case ClaimTypes.Email:
                    case JwtRegisteredClaimNames.Email:
                        ris.Email = c.Value;
                        break;

                    case ClaimTypes.NameIdentifier:
                    case JwtRegisteredClaimNames.NameId:
                        ris.Id = Convert.ToInt32(c.Value);
                        break;

                    case JwtRegisteredClaimNames.Jti:
                        ris.Jti = c.Value;
                        break;

                    case JwtRegisteredClaimNames.Prn:
                        ris.Prn = c.Value;
                        break;
                }
            }

            return ris;
        }
    }
}
