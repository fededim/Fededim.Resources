using Microsoft.AspNetCore.Identity;

namespace Fededim.Utilities.Models.DB
{
    public class UserToken : IdentityUserToken<long>
    {
        public virtual User User { get; set; }
    }
}
