using Microsoft.AspNetCore.Identity;

namespace Fededim.Utilities.Models.DB
{
    public class UserClaim : IdentityUserClaim<long>
    {
        public virtual User User { get; set; }
    }
}
