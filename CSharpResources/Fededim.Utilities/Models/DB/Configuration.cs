using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace Fededim.Utilities.Models.DB
{
    [Table("Configuration", Schema = "Data")]
    public class Configuration : IKey
    {
        [Key, MaxLength(50)]
        public string Key { get; set; }


        [MaxLength(256)]
        public string Description { get; set; }


        [Required, MaxLength(100)]
        public string Value { get; set; }
    }
}
