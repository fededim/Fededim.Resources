using Fededim.Utilities.Models.DB;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.Identity.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using System;
using System.Collections.Generic;
using System.Linq;

namespace Fededim.Utilities.Models
{
    public class SampleDBContext : IdentityDbContext<User, Role, long, UserClaim, UserRole, UserLogin, RoleClaim, UserToken>
    {
        public DbSet<DB.Log> Logs { get; set; }
        public DbSet<LogApi> LogApis { get; set; }

        public DbSet<Configuration> Configurations { get; set; }

        public DbSet<UserRefreshToken> UserRefreshTokens { get; set; }

        IConfiguration Config { get; set; }

        public SampleDBContext() : base()
        {

        }

        public SampleDBContext(DbContextOptions<SampleDBContext> options) : base(options)
        {
        }


        public SampleDBContext(DbContextOptions<SampleDBContext> options, IConfiguration configuration) : base(options)
        {
            Config = configuration;
        }

        protected override void OnConfiguring(DbContextOptionsBuilder optionsBuilder)
        {
            if (!optionsBuilder.IsConfigured)
            {
                if (Config != null)
                    optionsBuilder.UseSqlServer(Config.GetConnectionString("DefaultConnection"), x => x.CommandTimeout(30)); // UseNetTopologySuite // EnableSensitiveDataLogging()  //.EnableRetryOnFailure());
                else
                {
                    // Used for migrations where we do not have Config
                    optionsBuilder.UseSqlServer("Server = <host>; Database = <db>; User = <user>; Password = <password>; MultipleActiveResultSets=True; Application Name=<app name>;", x => x.CommandTimeout(30));
                }
            }
        }


        /// <summary>
        /// Creates a new context
        /// </summary>
        /// <param name="conf"></param>
        /// <returns></returns>
        public static SampleDBContext CreateContext(IConfiguration conf)
        {
            DbContextOptionsBuilder<SampleDBContext> builder = new DbContextOptionsBuilder<SampleDBContext>();
            builder.UseSqlServer(conf.GetConnectionString("DefaultConnection"), x => x.CommandTimeout(30)); // EnableSensitiveDataLogging()  //.EnableRetryOnFailure());
            return new SampleDBContext(builder.Options);
        }


        protected override void OnModelCreating(ModelBuilder mb)
        {
            base.OnModelCreating(mb);

            ModelIdentity(mb);

            // create unique index
            //mb.Entity<p>().HasIndex(p => new { p.prop1, p.prop2 }).IsUnique();          

            // Constraints
            //mb.Entity<i>().HasIndex(i => new { i.prop1, i.prop2, i.prop3 }).IncludeProperties(p => new { p.prop4, p.prop5 });
            //mb.Entity<c>().HasKey(c => new { c.id1, c.id2 });

            //mb.Entity<e>().HasOne(e => e.t).WithMany().OnDelete(DeleteBehavior.Restrict);
            //mb.Entity<e>().HasOne(e => e.m).WithMany().OnDelete(DeleteBehavior.Restrict);
            
            mb.Entity<DB.Log>().HasOne(e => e.User).WithMany().OnDelete(DeleteBehavior.Cascade);
            mb.Entity<LogApi>().HasOne(e => e.User).WithMany().OnDelete(DeleteBehavior.Cascade);

            // Added fields default value
            //mb.Entity<c>().Property(c => c.propdef).HasDefaultValue(false);

            // DATA //

            // Seed Identity tables
            List<Role> roles = new List<Role>() {
                new Role { Id=1, Name = "Admin", NormalizedName = "ADMIN" },
                new Role { Id=2, Name = "User", NormalizedName = "USER" } };
            mb.Entity<Role>().HasData(roles);

            var passwordHasher = new PasswordHasher<User>();
            var admin = new User { Id = 1, UserName = "admin", NormalizedUserName = "ADMIN", Email = "admin@xxx.com", NormalizedEmail = "ADMIN@XXX.COM", EmailConfirmed = true, SecurityStamp = Guid.NewGuid().ToString() };
            admin.PasswordHash = passwordHasher.HashPassword(admin, "Adminpwd"); // do not know why we need to pass user, it is not even used in source code https://github.com/aspnet/Identity/blob/master/src/Core/PasswordHasher.cs 
            var user = new User { Id = 2, UserName = "user", NormalizedUserName = "USER", Email = "user@xxx.com", NormalizedEmail = "USER@XXX.COM", EmailConfirmed = true, SecurityStamp = Guid.NewGuid().ToString() };
            user.PasswordHash = passwordHasher.HashPassword(user, "Userpwd"); // do not know why we need to pass user, it is not even used in source code https://github.com/aspnet/Identity/blob/master/src/Core/PasswordHasher.cs 
            mb.Entity<User>().HasData(new List<User>() { admin, user });

            var userRoles = new List<UserRole> { new UserRole { UserId = 1, RoleId = 1 }, new UserRole { UserId = 1, RoleId = 2 }, new UserRole { UserId = 2, RoleId = 2 } };
            mb.Entity<UserRole>().HasData(userRoles);

            // populate enums tables
            //mb.Entity<enum>().HasData(Enum.GetValues(typeof(enumtype)).OfType<enumType>().Select(e => new enum() { Id = e, Description = e.ToString() }));

            // populate tables
            mb.Entity<Configuration>().HasData(new Configuration() { Key = "EnableRetry", Description = "Enables retry on database", Value = "true" });
        }

        private void ModelIdentity(ModelBuilder mb)
        {
            // Microsoft Identity          

            // change default schema
            mb.Entity<User>().ToTable("AspNetUsers", "User");
            mb.Entity<Role>().ToTable("AspNetRoles", "User");
            mb.Entity<UserRole>().ToTable("AspNetUserRoles", "User");
            mb.Entity<RoleClaim>().ToTable("AspNetRoleClaims", "User");
            mb.Entity<UserClaim>().ToTable("AspNetUserClaims", "User");
            mb.Entity<UserLogin>().ToTable("AspNetUserLogins", "User");
            mb.Entity<UserToken>().ToTable("AspNetUserTokens", "User");

            // User
            mb.Entity<User>().HasMany(e => e.Claims).WithOne().HasForeignKey(uc => uc.UserId).IsRequired();  // Each User can have many UserClaims           
            mb.Entity<User>().HasMany(e => e.Logins).WithOne().HasForeignKey(ul => ul.UserId).IsRequired();  // Each User can have many UserLogins            
            mb.Entity<User>().HasMany(e => e.Tokens).WithOne().HasForeignKey(ut => ut.UserId).IsRequired();  // Each User can have many UserTokens            
            mb.Entity<User>().HasMany(e => e.UserRoles).WithOne().HasForeignKey(ur => ur.UserId).IsRequired();  // Each User can have many entries in the UserRole join table

            // Role
            mb.Entity<Role>().HasMany(e => e.UserRoles).WithOne(e => e.Role).HasForeignKey(ur => ur.RoleId).IsRequired();  // Each Role can have many entries in the UserRole join table
            mb.Entity<Role>().HasMany(e => e.RoleClaims).WithOne(e => e.Role).HasForeignKey(rc => rc.RoleId).IsRequired();  // Each Role can have many associated RoleClaims

            // User Role
            mb.Entity<UserRole>().HasOne(e => e.Role).WithMany(e => e.UserRoles).HasForeignKey(ur => ur.RoleId).IsRequired();
            mb.Entity<UserRole>().HasOne(e => e.User).WithMany(e => e.UserRoles).HasForeignKey(ur => ur.UserId).IsRequired();

            // User Claim
            mb.Entity<UserClaim>().HasOne(e => e.User).WithMany(e => e.Claims).HasForeignKey(ur => ur.UserId).IsRequired();

            // User Token
            mb.Entity<UserToken>().HasOne(e => e.User).WithMany(e => e.Tokens).HasForeignKey(ur => ur.UserId).IsRequired();

            // User Token
            mb.Entity<UserLogin>().HasOne(e => e.User).WithMany(e => e.Logins).HasForeignKey(ur => ur.UserId).IsRequired();

            // Role Claim
            mb.Entity<RoleClaim>().HasOne(e => e.Role).WithMany(e => e.RoleClaims).HasForeignKey(ur => ur.RoleId).IsRequired();

            // UserRefreshToken
            mb.Entity<UserRefreshToken>().HasKey(urt => new { urt.UserId, urt.TokenGuid, urt.RefreshToken });
        }
    }
}
