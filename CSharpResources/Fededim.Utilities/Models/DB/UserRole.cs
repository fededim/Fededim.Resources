using Microsoft.AspNetCore.Identity;

namespace Fededim.Utilities.Models.DB
{
    public class UserRole : IdentityUserRole<long>
    {
        public virtual User User { get; set; }
        public virtual Role Role { get; set; }
    }
}
