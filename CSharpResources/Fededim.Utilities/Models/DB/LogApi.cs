using System;
using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace Fededim.Utilities.Models.DB
{
    [Table("LogApi", Schema = "Log")]
    public class LogApi
    {
        [Key, DatabaseGenerated(DatabaseGeneratedOption.Identity)]
        public long Id { get; set; }

        [Required]
        public DateTime Timestamp { get; set; }

        [Required, MaxLength(50)]
        public string Host { get; set; }

        public long? UserId { get; set; }

        [Required, MaxLength(10)]
        public string Method { get; set; }

        [Required, MaxLength(2000)]
        public string Url { get; set; }

        [MaxLength(4194304)]
        public string Request { get; set; }

        [Required]
        public int Result { get; set; }

        [MaxLength(4194304)]
        public string Response { get; set; }

        [Required]
        public int ElapsedMs { get; set; }

        public virtual User User { get; set; }
    }
}
