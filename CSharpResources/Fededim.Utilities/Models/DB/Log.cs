using System;
using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace Fededim.Utilities.Models.DB
{
    [Table("Log", Schema = "Log")]
    public class Log
    {
        [Key, DatabaseGenerated(DatabaseGeneratedOption.Identity)]
        public long Id { get; set; }

        [Required]
        public DateTime Timestamp { get; set; }

        [MaxLength(50)]
        public string Host { get; set; }

        public long? UserId { get; set; }

        [Required, MaxLength(80)]
        public string Source { get; set; }

        [Required, MaxLength(20)]
        public string Level { get; set; }

        [Required, MaxLength(1024)]
        public string Message { get; set; }

        public virtual User User { get; set; }
    }
}
