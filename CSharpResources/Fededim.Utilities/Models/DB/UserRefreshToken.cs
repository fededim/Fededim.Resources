using System;
using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace Fededim.Utilities.Models.DB
{
    [Table("UserRefreshToken", Schema = "User")]
    public class UserRefreshToken
    {
        public long UserId { get; set; }
        [MaxLength(64)]
        public string TokenGuid { get; set; }           // must contain the token JTI claim
        [MaxLength(64)]
        public string RefreshToken { get; set; }
        public DateTime Validity { get; set; }

        public virtual User User { get; set; }
    }
}
