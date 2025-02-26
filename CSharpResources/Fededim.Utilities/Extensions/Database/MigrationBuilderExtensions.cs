using Microsoft.EntityFrameworkCore.Migrations;
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Runtime.CompilerServices;

namespace Fededim.Utilities.Extensions.Database
{
    public static class MigrationBuilderExtensions
    {
        public static string GetAssemblyResource<T>(this T cl, string resourceName) where T : class
        {
            Assembly assem = cl.GetType().Assembly;
            var stream = assem.GetManifestResourceStream(resourceName);
            if (stream == null)
                return string.Empty;

            using (stream)
            {
                using (var reader = new StreamReader(stream))
                {
                    return reader.ReadToEnd();
                }
            }
        }


        public static List<string> GetAssemblyResources<T>(string resourceNameToken) where T : class
        {
            Assembly assem = typeof(T).Assembly;

            // Debug
            //Console.WriteLine($"Assembly {assem.FullName} resourceToken {resourceNameToken}");
            //foreach (var r in assem.GetManifestResourceNames())
            //{
            //    Console.WriteLine($"found resource {r}");
            //}

            return assem.GetManifestResourceNames().Where(rn => rn.Contains(resourceNameToken)).ToList();
        }



        public static int GetNIndexOf(this string s, char c, int ieth)
        {
            int num = 0, pos = 0;
            foreach (char ch in s)
            {
                if (ch == c)
                    if (num++ == ieth)
                        break;
                pos++;
            }

            return pos;
        }




        private static string GetObjectNameFromResourceKey(string prefixResourceKey, string r)
        {
            return r.Substring(prefixResourceKey.Length + 1, r.Length - (prefixResourceKey.Length + 1) - 4);
        }


        private static string GetDbObjectsResourceKey<T>() where T : class
        {
            var att = (MigrationDbObjectsResourceKeyAttribute)typeof(T).Assembly.GetCustomAttribute(typeof(MigrationDbObjectsResourceKeyAttribute));

            // [assembly: MigrationDbObjectsResourceKey("<Project>.DB.MigrationDbObjects")]
            if (att == null)
                throw new ArgumentException($"Please define the attribute MigrationDbObjectsResourceKey in the assembly info file",typeof(T).Name);

            return att.ResourceKey;
        }


        public static void CreateMigrationDBObjects<T>(this T cl, MigrationBuilder mb, [CallerFilePath] string migrationFile = "") where T : Migration
        {
            string resourceKey = $"{GetDbObjectsResourceKey<T>()}._{Path.GetFileNameWithoutExtension(migrationFile)}";

            // Create functions
            string prefixResource = $"{resourceKey}.Functions";
            foreach (var r in GetAssemblyResources<T>(prefixResource))
            {
                string fnName = GetObjectNameFromResourceKey(prefixResource, r);
                Console.WriteLine($"Creating or updating FUNCTION {fnName}");

                mb.Sql(cl.GetAssemblyResource(r));
            }

            // Create stored procedures
            prefixResource = $"{resourceKey}.SP";
            foreach (var r in GetAssemblyResources<T>(prefixResource))
            {
                string procName = GetObjectNameFromResourceKey(prefixResource, r);
                Console.WriteLine($"Creating or updating SP {procName}");

                mb.Sql(cl.GetAssemblyResource(r));
            }
        }




        public static HashSet<string> IndexAllDBObjects<T>(this T cl, string resourceKey) where T : Migration
        {
            HashSet<string> indexObjects = new HashSet<string>();

            string prefixResource = $"{resourceKey}.SP";
            // Index all SP
            foreach (var r in GetAssemblyResources<T>(prefixResource))
            {
                string procName = GetObjectNameFromResourceKey(resourceKey, r);
                indexObjects.Add(procName);
            }

            prefixResource = $"{resourceKey}.Functions";
            // Index all Functions
            foreach (var r in GetAssemblyResources<T>(prefixResource))
            {
                string procName = GetObjectNameFromResourceKey(resourceKey, r);
                indexObjects.Add(procName);
            }

            return indexObjects;
        }

        public static void DeleteMigrationDBObjects<T>(this T cl, MigrationBuilder mb, [CallerFilePath] string migrationFile = "") where T : Migration
        {
            string resourceKey = $"{GetDbObjectsResourceKey<T>()}._{Path.GetFileNameWithoutExtension(migrationFile)}";

            // Drop SP of the current migration
            string prefixResource = $"{resourceKey}.SP";
            foreach (var r in GetAssemblyResources<T>(prefixResource))
            {
                string procKey = GetObjectNameFromResourceKey(resourceKey, r);

                string procName = procKey.Substring(3);

                Console.WriteLine($"Dropping SP {procName}");
                mb.Sql($"DROP PROCEDURE {procName}");
            }


            // Drop functions of the current migration
            prefixResource = $"{resourceKey}.Functions";
            foreach (var r in GetAssemblyResources<T>(prefixResource))
            {
                string funKey = GetObjectNameFromResourceKey(resourceKey, r);

                string funName = funKey.Substring(10);

                Console.WriteLine($"Dropping FUNCTION {funName}");
                mb.Sql($"DROP FUNCTION {funName}");
            }
        }


        public static void CreatePreviousMigrationsDBObjects<T>(this T cl, MigrationBuilder mb, [CallerFilePath] string migrationFile = "") where T : Migration
        {
            string migrationKey, prefixResource;

            string currentMigration = Path.GetFileNameWithoutExtension(migrationFile);

            var resourceKey = $"{GetDbObjectsResourceKey<T>()}";

            Dictionary<string, Stack<string>> index = IndexAllDbObjects<T>(resourceKey, currentMigration);

            // we cycle the currentMigration dbObjects and we create older ones if they are indexed
            migrationKey = $"{resourceKey}._{currentMigration}";

            // Functions
            prefixResource = $"{migrationKey}.Functions";
            foreach (var r in GetAssemblyResources<T>(prefixResource))
            {
                string funName = GetObjectNameFromResourceKey(prefixResource, r);

                var key = $"Functions.{funName}";

                if (!index.ContainsKey(key))
                    continue;

                string resKey = index[key].Peek();

                Console.WriteLine($"Recreating previous Function {funName} (ResourceKey {resKey})");
                mb.Sql(cl.GetAssemblyResource(resKey));
            }

            // SP
            prefixResource = $"{migrationKey}.SP";
            foreach (var r in GetAssemblyResources<T>(prefixResource))
            {
                string procName = GetObjectNameFromResourceKey(prefixResource, r);

                var key = $"SP.{procName}";

                if (!index.ContainsKey(key))
                    continue;

                string resKey = index[key].Peek();

                Console.WriteLine($"Recreating previous SP {procName} (ResourceKey {resKey})");
                mb.Sql(cl.GetAssemblyResource(resKey));
            }

        }

        private static Dictionary<string, Stack<string>> IndexAllDbObjects<T>(string resourceKey, string currentMigration = null) where T : Migration
        {
            // Index all previous version db objects, key is db object name, value is a stack of "migrations" (resource keys) where it is defined (from the most recent to the oldest one)
            var index = new Dictionary<string, Stack<string>>();

            foreach (var migr in GetAllMigrations())
            {
                if (migr == currentMigration)
                    break;

                //Console.WriteLine($"Index: analyzing migration {migr}");
                var migrationKey = $"{resourceKey}.{migr}";

                // Index SP
                var prefixResource = $"{migrationKey}.SP";
                foreach (var r in GetAssemblyResources<T>(prefixResource))
                {
                    string procName = GetObjectNameFromResourceKey(prefixResource, r);

                    var key = $"SP.{procName}";

                    if (!index.ContainsKey(key))
                        index[key] = new Stack<string>();

                    index[key].Push(r);
                    //Console.WriteLine($"Index: key {key} added resourcekey {r}");
                }


                // Index Functions
                prefixResource = $"{migrationKey}.Functions";
                foreach (var r in GetAssemblyResources<T>(prefixResource))
                {
                    string funName = GetObjectNameFromResourceKey(prefixResource, r);

                    var key = $"Functions.{funName}";

                    if (!index.ContainsKey(key))
                        index[key] = new Stack<string>();

                    index[key].Push(r);
                    //Console.WriteLine($"Index: key {key} added resourcekey {r}");
                }
            }

            return index;
        }

        public static List<string> GetAllMigrations()
        {
            var ris = new List<string>();

            foreach (var f in Directory.EnumerateFiles("Migrations"))
            {
                if (f.Contains(".Designer.cs"))
                    continue;

                ris.Add(Path.GetFileNameWithoutExtension(f));
            }

            ris.Sort();

            return ris;
        }
    }
}
