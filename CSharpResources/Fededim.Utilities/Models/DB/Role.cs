using Microsoft.AspNetCore.Identity;
using System.Collections.Generic;

namespace Fededim.Utilities.Models.DB
{
    public class Role : IdentityRole<long>
    {
        public virtual ICollection<UserRole> UserRoles { get; set; }
        public virtual ICollection<RoleClaim> RoleClaims { get; set; }
    }
}
