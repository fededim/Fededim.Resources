# TSqlResources © 2005 - current Federico Di Marco
A set of utilites for Sql Server released as open source under the MIT license.

# Stored Procedures (SPs folder)

## [spReapplyLoginToDatabases.sql](https://github.com/fededim/Fededim.Resources/tree/master/TSqlResources/SPs/spReapplyLoginToDatabases.sql)

### Parameters
	- @loginname: a SQL LIKE pattern to specify the login (only the first match is taken)
	- @grantExecute: a BIT which specifies whether to grant the execute permission on stored procedure for the user

### OUTPUT
A log table with these columns:

	- [Database]: database name to which the LogMessage applies
	- [LogMessage]: the message logged during the execution

### USAGE
	- exec spReapplyLoginToDatabases 'test' -- recreates the user for the test login in all databases of the server with db_datareader and db_datawriter role
	- exec spReapplyLoginToDatabases 'test',1 -- recreates the user for the test login in all databases of the server with db_datareader and db_datawriter role and grants also the permission to execute the stored procedures

## [spSearchTables.sql](https://github.com/fededim/Fededim.Resources/tree/master/TSqlResources/SPs/spSearchTables.sql)

A helper stored procedure which allows to search tables or columns either by name or by value in all databases in a server. [Link to CodeProject article.](https://www.codeproject.com/Articles/5370606/spSearchTables-a-helper-T-SQL-stored-procedure-for)

### Parameters

exec spSearchTables @dbSearchPattern, @tableSearchPattern, @columnSearchPattern, @valuePattern

	- @dbSearchPattern: a SQL LIKE pattern to filter databases, set to NULL to search in all databases
	- @schemaSearchPattern: a SQL LIKE pattern to filter schemas, set to NULL to search in all schemas
	- @tableSearchPattern: a SQL LIKE pattern to filter tables, set to  NULL to search in all tables
	- @columnTypeSearchPattern: a SQL LIKE pattern to filter column type, set to NULL to search in all column types	
	- @columnSearchPattern: a SQL LIKE pattern to filter columns, set to NULL to search in all columns
	- @valuePattern: a SQL LIKE pattern to filter column value, set to NULL to not to search on column values
 
### OUTPUT

A table with these columns:

	- [Database]: database names matching @dbSearchPattern parameter
	- [Schema]: schema names matching @tableSearchPattern parameter
	- [Table]: table names  matching @columnSearchPattern parameter
	- [FullTableName]: it's just the concatenation of database + schema + table
	- [MatchingColumns]: comma separated list of column names matching the @columnsSearchPattern
	- [MatchingSelect]: the select statement returning the columns and rows matching the @valuePattern (it supports all column datatypes)

### USAGE

	- exec spSearchTables NULL,NULL,NULL,NULL,NULL,NULL - returns all tables with all columns in all databases in the server
	- exec spSearchTables 'North%','d%',NULL,NULL,NULL,NULL - returns all tables with all columns in all databases starting with North% and having d% in the schema in the server
	- exec spSearchTables 'North%',NULL,'S%',NULL,NULL,NULL - returns tables starting with S% with all columns in databases starting with North% in the server
	- exec spSearchTables 'North%',NULL,'S%','%int%',NULL,NULL - returns tables starting with S% with all columns in databases starting with North% in the server and type %int%
	- exec spSearchTables 'North%',NULL,'S%',NULL,'P%',NULL - returns tables starting with S% with columns starting with P% in databases starting with North% in the server 
	- exec spSearchTables 'North%',,NULL,'S%',NULL,'P%','30%' - returns tables starting with S% with columns starting with P% whose value matches 30% in databases starting with North% in the server
	- exec spSearchTables NULL,NULL,NULL,NULL,NULL,'30%' - returns all table and all columns whose value matches 30% in all databases in the server
	- exec spSearchTables NULL,NULL,NULL,'geo%',NULL,'POINT(-122.35900 47.65129)' - WKT query: returns all table and all columns whose columntype is spatial (e.g. geometry or geography) and contain the specified WKT entity


## [AIDbMaintenance.sql](https://github.com/fededim/Fededim.Resources/tree/master/TSqlResources/SPs/AIDbMaintenance.sql)

DbMaintenance - A helper script to schedule periodically to maintain fragmented indexes, optionally rebuild heaps with forwarded records, and update statistics which need it.
Requires SQL Server 2016 SP1 or later, including Standard and Express editions.

### Parameters

exec dbo.spDbMaintenance (all optional)

	-@ReorganizeThreshold       Min. fragmentation % to take an action on a rowstore index
                                (default 15)
	-@RebuildThreshold          Min. fragmentation % to REBUILD instead of REORGANIZE
                                (default 30). If page locks are disabled, eligible indexes
                                require REBUILD, subject to the rebuild page limit.
	-@MinPageCount              Min. in-row heap pages / rowstore leaf pages for maintenance
                                (default 1000). Does not filter columnstore or statistics.
	-@MaxRebuildPageCount       Max. pages per target partition, or unpartitioned object,
                                allowed for an offline REBUILD. NULL = no limit (default).
                                Larger rowstore targets are reorganized if page locks are
                                enabled; otherwise they are skipped. Larger heaps are skipped.
                                Heap rebuilds may also rebuild nonclustered indexes, so this
                                is not a limit on the total work performed.
	-@ColumnstoreDeletedPercent Min. aggregate deleted-row % across compressed rowgroups in a
                                partition to REORGANIZE a columnstore index (default 20)
	-@StatsModificationPercent  Modified-row percentage threshold for statistics (default 10),
                                based on the stored statistic row count; see formula below.
	-@HeapRebuildEnabled        1 = rebuild eligible heaps using ALTER TABLE ... REBUILD.
                                0 = skip heap discovery in execution mode (default).
                                Preview lists qualifying heaps even when this is 0.
	-@HeapForwardedPercent      Min. sampled forwarded-record % for a heap to qualify for
                                rebuild or preview reporting (default 10)
	-@MaxDurationMinutes        No new maintenance command starts after this elapsed time.
                                Includes discovery time, but does not stop discovery or an
                                operation already running. NULL = no limit (default).
	-@LockTimeoutSeconds        Seconds to wait for an object lock before the operation fails.
                                -1 = wait forever; otherwise 0 to 2147483 (default 60).
                                Does not control the concurrency application lock.
	-@IndexRebuildEnabled       1 = maintain rowstore and columnstore indexes (default).
                                0 = skip index discovery and maintenance. Controls both
                                REBUILD and REORGANIZE; does not control heap maintenance.
	-@StatisticsRebuildEnabled  1 = perform eligible UPDATE STATISTICS operations (default).
                                0 = skip this phase. Index rebuilds can still refresh their
                                own statistics.
	-@PreviewMode               1 = return planned work without executing maintenance.
                                0 = execute maintenance (default). Preview honors the phase
                                switches, includes heap advisory rows, performs discovery,
                                and acquires the same concurrency lock as execution.
                                Preview is a snapshot, not a guarantee of work completed
                                within the configured duration.
	-@StatsSizeSensitiveEnabled 1 = use the size-sensitive statistics threshold (default).
                                0 = use only the percentage threshold.
	-@StatsSizeThresholdFactor  Positive factor in the size-sensitive formula (default 1000).
                                A smaller factor can make statistics eligible sooner.
	-@StatsMinimumModificationCount
                                Positive floor for the size-sensitive branch (default 500).
                                This is not a floor for the percentage branch.

 
### OUTPUT

OUTPUT: a table with all the T-SQL statement which will be run to rebuild the indexes and update statistics. PRINTs report progress, skipped operations, errors and totals. If operations fail, an error is raised after the remaining eligible work is attempted subject to the duration limit. Heap advisory rows are available in preview only.
When @PreviewMode=1 only the table is displayed showing the planned commands for analysis and inspection.

### USAGE

    - exec dbo.spDbMaintenance: maintain indexes and statistics with default thresholds; do not rebuild heaps.
    - exec dbo.spDbMaintenance @PreviewMode = 1: display planned index/statistics work and qualifying heap advisories, but no maintenance commands are executed.
    - exec dbo.spDbMaintenance @PreviewMode = 1, @HeapRebuildEnabled = 1: preview eligible heap rebuilds together with default index/statistics work
    - exec dbo.spDbMaintenance @IndexRebuildEnabled = 0, @HeapRebuildEnabled = 0, @StatisticsRebuildEnabled = 1: maintain statistics only, using the default size-sensitive threshold.
    - exec dbo.spDbMaintenance @IndexRebuildEnabled = 1, @StatisticsRebuildEnabled = 0: maintain indexes only; index rebuilds can still refresh index statistics.
    - exec dbo.spDbMaintenance @HeapRebuildEnabled = 1, @MaxRebuildPageCount = 100000, @MaxDurationMinutes = 30, @LockTimeoutSeconds = 15: nclude heap rebuilds, cap each rebuild target at 100000 pages, and stop starting new commands after 30 minutes. Wait up to 15 seconds for object locks.
    - exec dbo.spDbMaintenance @PreviewMode = 1, @IndexRebuildEnabled = 0, @StatsSizeSensitiveEnabled = 1, @StatsSizeThresholdFactor = 500, @StatsMinimumModificationCount = 500: Preview statistics-only work with a lower size-sensitive factor. The 500-modification floor applies only to the size-sensitive branch.
    - exec dbo.spDbMaintenance @IndexRebuildEnabled = 0, @StatsSizeSensitiveEnabled = 0, @StatsModificationPercent = 10: Maintain statistics only when the percentage threshold is reached.


# Functions (Functions folder)

## [fnGetCalendarTable.sql](https://github.com/fededim/Fededim.Resources/tree/master/TSqlResources/Functions/fnGetCalendarTable.sql)

A helper table valued function which returns a range of dates from a startDate to an endDate using the stepMin step in minutes

### PARAMETERS
	- @startDate: the date from which the calendar table should start
	- @endDate: the date to which the calendar table should stop
	- @stepMin: the increment step in minutes
 
### OUTPUT
	- A calendar table

### USAGE
	- SELECT * FROM fnGetCalendarTable('2020-08-12T08:01:33.123456','2020-08-13T09:15:22',10) OPTION (MAXRECURSION 0)


# Scripts (Scripts folder)

## [DbMaintenance.sql](https://github.com/fededim/Fededim.Resources/tree/master/TSqlResources/Scripts/dbMaintenance.sql)
A helper script which must be scheduled every day (or more frequently) to rebuild all fragmented indexes of a database and update all its statistics

## [QueryExcelCsv.sql](https://github.com/fededim/Fededim.Resources/tree/master/TSqlResources/Scripts/QueryExcelCsv.sql)
An example script which can be used to query CSV or XSLX files directly in Sql Management Studio without importing them into tables. [Link to CodeProject article.](https://www.codeproject.com/Tips/5370433/Query-Excel-or-CSV-files-with-T-SQL)

## [BackupDatabase.Sql](https://github.com/fededim/Fededim.Resources/tree/master/TSqlResources/Scripts/BackupDatabase.sql)
A helper script which will perform a backup of a database to a network location mounted on letter Z:
