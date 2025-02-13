using Microsoft.AspNetCore.Identity;
using System;

namespace Fededim.Utilities.Models.DB
{
    public class UserLogin : IdentityUserLogin<long>
    {
        public virtual User User { get; set; }
    }
}
