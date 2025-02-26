using Microsoft.AspNetCore.Identity;

namespace Fededim.Utilities.Models.DB
{
    public class RoleClaim : IdentityRoleClaim<long>
    {
        public virtual Role Role { get; set; }
    }
}
