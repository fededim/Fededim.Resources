using Microsoft.EntityFrameworkCore;
using System;
using System.Collections.Generic;
using System.Data.Common;
using System.Reflection;
using System.Threading.Tasks;
using System.Transactions;

namespace Fededim.Utilities.Extensions.Database
{
    /// <summary>
    /// Older extensions, probably not needed anymore
    /// </summary>

    public static class DbContextExtensions
    {
        static Dictionary<String, PropertyInfo[]> cacheProperties = new Dictionary<string, PropertyInfo[]>();

        static PropertyInfo[] GetCachedProperties(Type t)
        {
            if (!cacheProperties.ContainsKey(t.FullName))
                cacheProperties[t.FullName] = t.GetProperties(System.Reflection.BindingFlags.Public | System.Reflection.BindingFlags.Instance);

            return cacheProperties[t.FullName];
        }

        public static Task<int> ExecuteNonQueryAsync(this DbContext context, FormattableString sql, int? timeout = null)
        {
            //using (var conn = context.Database.GetDbConnection())
            //    return ExecuteNonQueryAsync(conn, sql, timeout);
            return ExecuteNonQueryAsync(context.Database.GetDbConnection(), sql, timeout);
        }

        public static async Task<int> ExecuteNonQueryAsync(this DbConnection connection, FormattableString sql, int? timeout = null)
        {
            using (var command = connection.CreateCommand())
            {
                command.CommandText = sql.Format;
                if (timeout.HasValue)
                    command.CommandTimeout = timeout.Value;

                CreateParameters(connection.GetType(), command, sql);

                await connection.OpenAsync();

                return (int)ConvertValue(await command.ExecuteNonQueryAsync(), typeof(int));
            }
        }

        public static int ExecuteNonQuery(this DbContext context, FormattableString sql, int? timeout = null)
        {
            //using (var conn = context.Database.GetDbConnection())
            //    return conn.ExecuteNonQuery(sql, timeout);
            return context.Database.GetDbConnection().ExecuteNonQuery(sql, timeout);
        }

        public static int ExecuteNonQuery(this DbConnection connection, FormattableString sql, int? timeout = null)
        {
            using (var command = connection.CreateCommand())
            {
                command.CommandText = sql.Format;
                if (timeout.HasValue)
                    command.CommandTimeout = timeout.Value;

                CreateParameters(connection.GetType(), command, sql);

                connection.Open();

                return (int)ConvertValue(command.ExecuteNonQuery(), typeof(int));
            }
        }

        public static Task<T> ExecuteScalarAsync<T>(this DbContext context, FormattableString sql, int? timeout = null)
        {
            //using (var conn = context.Database.GetDbConnection())
            //    return conn.ExecuteScalarAsync<T>(sql, timeout);
            return context.Database.GetDbConnection().ExecuteScalarAsync<T>(sql, timeout);
        }
        public static async Task<T> ExecuteScalarAsync<T>(this DbConnection connection, FormattableString sql, int? timeout = null)
        {
            using (var command = connection.CreateCommand())
            {
                command.CommandText = sql.Format;
                if (timeout.HasValue)
                    command.CommandTimeout = timeout.Value;

                CreateParameters(connection.GetType(), command, sql);

                await connection.OpenAsync();

                return (T)ConvertValue(await command.ExecuteScalarAsync(), typeof(T));
            }
        }

        public static T ExecuteScalar<T>(this DbContext context, FormattableString sql, int? timeout = null)
        {
            //using (var conn = context.Database.GetDbConnection())
            //    return ExecuteScalar<T>(conn, sql, timeout);
            return ExecuteScalar<T>(context.Database.GetDbConnection(), sql, timeout);
        }
        public static T ExecuteScalar<T>(this DbConnection connection, FormattableString sql, int? timeout = null)
        {
            using (var command = connection.CreateCommand())
            {
                command.CommandText = sql.Format;
                if (timeout.HasValue)
                    command.CommandTimeout = timeout.Value;

                CreateParameters(connection.GetType(), command, sql);

                connection.Open();

                return (T)ConvertValue(command.ExecuteScalar(), typeof(T));
            }
        }

        public static IList<T> ExecuteQuery<T>(this DbContext context, FormattableString sql, int? timeout = null) where T : new()
        {
            //using (var conn = context.Database.GetDbConnection())
            //    return ExecuteQuery<T>(conn, sql, timeout);
            return ExecuteQuery<T>(context.Database.GetDbConnection(), sql, timeout);
        }

        public static IList<T> ExecuteQuery<T>(this DbConnection connection, FormattableString sql, int? timeout = null) where T : new()
        {
            using (var command = connection.CreateCommand())
            {
                command.CommandText = sql.Format;
                if (timeout.HasValue)
                    command.CommandTimeout = timeout.Value;

                CreateParameters(connection.GetType(), command, sql);

                connection.Open();

                IList<T> ris = new List<T>();

                Dictionary<String, PropertyInfo> cacheProps = new Dictionary<string, PropertyInfo>();
                foreach (var p in GetCachedProperties(typeof(T)))
                    cacheProps.Add(p.Name, p);

                using (var reader = command.ExecuteReader())
                {
                    while (reader.Read())
                    {
                        T elem = new T();

                        // Fill elem object
                        for (int i = 0; i < reader.FieldCount; i++)
                        {
                            var cname = reader.GetName(i);
                            if (String.IsNullOrEmpty(cname) || !cacheProps.ContainsKey(cname))
                                continue;

                            SetValue(reader.GetValue(i), elem, cacheProps[cname]);
                        }

                        ris.Add(elem);
                    }
                }

                return ris;
            }
        }


        public static T ExecuteQueryMulti<T>(this DbContext context, FormattableString sql, int? timeout = null) where T : new()
        {
            //using (var conn = context.Database.GetDbConnection())
            //    return ExecuteQueryMulti<T>(conn, sql, timeout);
            return ExecuteQueryMulti<T>(context.Database.GetDbConnection(), sql, timeout);
        }

        public static T ExecuteQueryMulti<T>(this DbConnection connection, FormattableString sql, int? timeout = null) where T : new()
        {
            using (var command = connection.CreateCommand())
            {
                command.CommandText = sql.Format;
                if (timeout.HasValue)
                    command.CommandTimeout = timeout.Value;

                CreateParameters(connection.GetType(), command, sql);

                connection.Open();

                T ris = new T();

                using (var reader = command.ExecuteReader())
                {
                    // Each property is filled with the i-eth result set
                    foreach (var pT in GetCachedProperties(typeof(T)))
                    {
                        var genType = pT.PropertyType;
                        if (!genType.IsGenericType || genType.GetGenericTypeDefinition() != typeof(List<>))
                            throw new NotSupportedException($"PropertyType {pT.Name} must be an IList<>!");

                        Type itemType = genType.GetGenericArguments()[0];

                        var propRis = Activator.CreateInstance(genType);
                        pT.SetValue(ris, propRis);

                        Dictionary<String, PropertyInfo> cacheProps = new Dictionary<string, PropertyInfo>();
                        foreach (var p in GetCachedProperties(itemType))
                            cacheProps.Add(p.Name, p);

                        while (reader.Read())
                        {
                            object elem = Activator.CreateInstance(itemType);

                            // Fill elem object
                            for (int i = 0; i < reader.FieldCount; i++)
                            {
                                var cname = reader.GetName(i);
                                if (String.IsNullOrEmpty(cname) || !cacheProps.ContainsKey(cname))
                                    continue;

                                SetValue(reader.GetValue(i), elem, cacheProps[cname]);
                            }

                            genType.GetMethod("Add").Invoke(propRis, new[] { elem });
                        }

                        if (!reader.NextResult())
                            break;
                    }

                }

                return ris;
            }
        }

        public static Task<IList<T>> ExecuteQueryAsync<T>(this DbContext context, FormattableString sql, int? timeout = null) where T : new()
        {
            //using (var conn = context.Database.GetDbConnection())
            //    return ExecuteQueryAsync<T>(conn, sql, timeout);
            return ExecuteQueryAsync<T>(context.Database.GetDbConnection(), sql, timeout);
        }


        public static async Task<IList<T>> ExecuteQueryAsync<T>(this DbConnection connection, FormattableString sql, int? timeout = null) where T : new()
        {
            using (var command = connection.CreateCommand())
            {
                command.CommandText = sql.Format;
                if (timeout.HasValue)
                    command.CommandTimeout = timeout.Value;

                CreateParameters(connection.GetType(), command, sql);

                await connection.OpenAsync();

                IList<T> ris = new List<T>();

                Dictionary<String, PropertyInfo> cacheProps = new Dictionary<string, PropertyInfo>();
                foreach (var p in GetCachedProperties(typeof(T)))
                    cacheProps.Add(p.Name, p);

                using (var reader = await command.ExecuteReaderAsync())
                {
                    while (reader.Read())
                    {
                        T elem = new T();

                        // Fill elem object
                        for (int i = 0; i < reader.FieldCount; i++)
                        {
                            var cname = reader.GetName(i);
                            if (String.IsNullOrEmpty(cname) || !cacheProps.ContainsKey(cname))
                                continue;

                            SetValue(reader.GetValue(i), elem, cacheProps[cname]);
                        }

                        ris.Add(elem);
                    }
                }

                return ris;
            }
        }

        private static void CreateParameters(Type connType, DbCommand command, FormattableString sql)
        {
            for (int i = 0; i < sql.ArgumentCount; i++)
            {
                var par = command.CreateParameter();
                par.Value = sql.GetArgument(i) ?? DBNull.Value;
                par.IsNullable = (par.Value == DBNull.Value);

                if (connType.Name == "SqlConnection")
                    par.ParameterName = $"@p{i}";
                else if (connType.Name == "OracleConnection")
                    par.ParameterName = $":p{i}";
                else
                    throw new NotSupportedException($"Connection type {connType.Name} not supported!");

                command.Parameters.Add(par);

                command.CommandText = command.CommandText.Replace($"{{{i}}}", par.ParameterName);
            }
        }

        private static void SetValue<T>(object value, T elem, PropertyInfo pi) where T : new()
        {
            Type t = pi.PropertyType;
            Type tn = Nullable.GetUnderlyingType(t);

            if (value == DBNull.Value)
                pi.SetValue(elem, null);
            else if (t.IsEnum)
                pi.SetValue(elem, Enum.Parse(t, value.ToString()));
            else if (tn != null)
            {
                if (tn.IsEnum)
                    pi.SetValue(elem, Enum.Parse(tn, value.ToString()));
                else
                    pi.SetValue(elem, Convert.ChangeType(value, tn));
            }
            else
                pi.SetValue(elem, Convert.ChangeType(value, t));
        }



        public static object Set(this DbContext context, Type T)
        {
            // Get the generic type definition
            MethodInfo method = typeof(DbContext).GetMethod(nameof(DbContext.Set), BindingFlags.Public | BindingFlags.Instance);

            // Build a method with the specific type argument you're interested in
            method = method.MakeGenericMethod(T);

            return method.Invoke(context, null);
        }


        private static object ConvertValue(object ris, Type t)
        {
            if (ris == DBNull.Value)
                return null;
            else return Convert.ChangeType(ris, t);
        }




        /// <summary>
        /// Creates a TransactionScope with ReadCommitted Isolation, the same level as sql server
        /// </summary>
        /// <returns>A transaction scope</returns>
        public static TransactionScope CreateReadCommittedScope()
        {
            var options = new TransactionOptions { IsolationLevel = System.Transactions.IsolationLevel.ReadCommitted, Timeout = TransactionManager.DefaultTimeout };

            return new TransactionScope(TransactionScopeOption.Required, options);
        }


        /// <summary>
        /// Creates a TransactionScope with RepeteableRead isolation
        /// </summary>
        /// <returns>A transaction scope</returns>
        public static TransactionScope CreateRepeteableReadScope()
        {
            var options = new TransactionOptions { IsolationLevel = System.Transactions.IsolationLevel.RepeatableRead, Timeout = TransactionManager.DefaultTimeout };

            return new TransactionScope(TransactionScopeOption.Required, options);
        }

    }
}
