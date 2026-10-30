/*********************************************************************************************
© 2026  Federico Di Marco <fededim@gmail.com>

DbMaintenance - A helper script to schedule periodically to maintain fragmented indexes,
optionally rebuild heaps with forwarded records, and update statistics which need it.
Requires SQL Server 2016 SP1 or later, including Standard and Express editions.
All REBUILD operations are OFFLINE and can take schema modification (Sch-M) locks;
REORGANIZE is online but still takes locks. Schedule execution in a maintenance window.
Express requires an external scheduler because SQL Server Agent is not included.
Deploy in the target database using a client supporting GO, such as SSMS or sqlcmd.
Execute outside a user transaction with sufficient maintenance and discovery permissions
(for example, as a member of db_owner).


PARAMETERS (all optional):
    @ReorganizeThreshold        Min. fragmentation % to take an action on a rowstore index
                                (default 15)
    @RebuildThreshold           Min. fragmentation % to REBUILD instead of REORGANIZE
                                (default 30). If page locks are disabled, eligible indexes
                                require REBUILD, subject to the rebuild page limit.
    @MinPageCount               Min. in-row heap pages / rowstore leaf pages for maintenance
                                (default 1000). Does not filter columnstore or statistics.
    @MaxRebuildPageCount        Max. pages per target partition, or unpartitioned object,
                                allowed for an offline REBUILD. NULL = no limit (default).
                                Larger rowstore targets are reorganized if page locks are
                                enabled; otherwise they are skipped. Larger heaps are skipped.
                                Heap rebuilds may also rebuild nonclustered indexes, so this
                                is not a limit on the total work performed.
    @ColumnstoreDeletedPercent  Min. aggregate deleted-row % across compressed rowgroups in a
                                partition to REORGANIZE a columnstore index (default 20)
    @StatsModificationPercent   Modified-row percentage threshold for statistics (default 10),
                                based on the stored statistic row count; see formula below.
    @HeapRebuildEnabled         1 = rebuild eligible heaps using ALTER TABLE ... REBUILD.
                                0 = skip heap discovery in execution mode (default).
                                Preview lists qualifying heaps even when this is 0.
    @HeapForwardedPercent       Min. sampled forwarded-record % for a heap to qualify for
                                rebuild or preview reporting (default 10)
    @MaxDurationMinutes         No new maintenance command starts after this elapsed time.
                                Includes discovery time, but does not stop discovery or an
                                operation already running. NULL = no limit (default).
    @LockTimeoutSeconds         Seconds to wait for an object lock before the operation fails.
                                -1 = wait forever; otherwise 0 to 2147483 (default 60).
                                Does not control the concurrency application lock.
    @IndexRebuildEnabled        1 = maintain rowstore and columnstore indexes (default).
                                0 = skip index discovery and maintenance. Controls both
                                REBUILD and REORGANIZE; does not control heap maintenance.
    @StatisticsRebuildEnabled   1 = perform eligible UPDATE STATISTICS operations (default).
                                0 = skip this phase. Index rebuilds can still refresh their
                                own statistics.
    @PreviewMode                1 = return planned work without executing maintenance.
                                0 = execute maintenance (default). Preview honors the phase
                                switches, includes heap advisory rows, performs discovery,
                                and acquires the same concurrency lock as execution.
                                Preview is a snapshot, not a guarantee of work completed
                                within the configured duration.
    @StatsSizeSensitiveEnabled  1 = use the size-sensitive statistics threshold (default).
                                0 = use only the percentage threshold.
    @StatsSizeThresholdFactor   Positive factor in the size-sensitive formula (default 1000).
                                A smaller factor can make statistics eligible sooner.
    @StatsMinimumModificationCount
                                Positive floor for the size-sensitive branch (default 500).
                                This is not a floor for the percentage branch.

    For initialized statistics with N stored rows and M modifications, update when M > 0
    and M reaches the following threshold:
        @StatsSizeSensitiveEnabled = 0:
            N * @StatsModificationPercent / 100
        @StatsSizeSensitiveEnabled = 1:
            MIN(N * @StatsModificationPercent / 100,
                MAX(@StatsMinimumModificationCount, SQRT(@StatsSizeThresholdFactor * N)))
    Uninitialized statistics and zero-row statistics with modifications are also eligible.
    Statistics eligibility is rechecked before execution; default sampling is used.
    Uninitialized statistics on empty tables/indexed views are skipped.


OUTPUT:
    - Execution: PRINT messages report progress, skipped operations, errors and totals.
      If operations fail, an error is raised after the remaining eligible work is attempted,
      subject to the duration limit. Heap advisory rows are available in preview only.
    - Preview: a result set shows planned commands, objects/partitions, measurements and
      selection reasons. Advisory rows have no maintenance command to execute.
    - An exclusive, database-scoped session application lock rejects overlapping calls
      immediately. It does not coordinate unrelated maintenance using a different lock.
      Normal completion and catchable errors release the lock. After client cancellation
      or an error bypassing CATCH, close the connection instead of returning it to a pool.


USAGE:
    - exec dbo.spDbMaintenance: maintain indexes and statistics with default thresholds; do not rebuild heaps.
    - exec dbo.spDbMaintenance @PreviewMode = 1: display planned index/statistics work and qualifying heap advisories, but no maintenance commands are executed.
    - exec dbo.spDbMaintenance @PreviewMode = 1, @HeapRebuildEnabled = 1: preview eligible heap rebuilds together with default index/statistics work
    - exec dbo.spDbMaintenance @IndexRebuildEnabled = 0, @HeapRebuildEnabled = 0, @StatisticsRebuildEnabled = 1: maintain statistics only, using the default size-sensitive threshold.
    - exec dbo.spDbMaintenance @IndexRebuildEnabled = 1, @StatisticsRebuildEnabled = 0: maintain indexes only; index rebuilds can still refresh index statistics.
    - exec dbo.spDbMaintenance @HeapRebuildEnabled = 1, @MaxRebuildPageCount = 100000, @MaxDurationMinutes = 30, @LockTimeoutSeconds = 15: nclude heap rebuilds, cap each rebuild target at 100000 pages, and stop starting new commands after 30 minutes. Wait up to 15 seconds for object locks.
    - exec dbo.spDbMaintenance @PreviewMode = 1, @IndexRebuildEnabled = 0, @StatsSizeSensitiveEnabled = 1, @StatsSizeThresholdFactor = 500, @StatsMinimumModificationCount = 500: Preview statistics-only work with a lower size-sensitive factor. The 500-modification floor applies only to the size-sensitive branch.
    - exec dbo.spDbMaintenance @IndexRebuildEnabled = 0, @StatsSizeSensitiveEnabled = 0, @StatsModificationPercent = 10: Maintain statistics only when the percentage threshold is reached.


VERSION HISTORY:
  20161001  fededim     Initial Release
  20261030  fededim     Rewritten for SQL Server 2022 Standard using Claude AI: page_count filter,
                        partitions, columnstore, disabled indexes, indexed views, QUOTENAME,
                        error handling, targeted statistics update, optional heap maintenance
                        with report of heaps having many forwarded records.
					    SQL Server 2016 SP1 compatibility baseline; heap command generation;
                        rebuild-size enforcement when page locks are disabled; independent
                        heap/index work without partition-alignment assumptions; execution-time
                        statistics rechecking and successful whole-index rebuild tracking;
                        deployment/execution SET options; parameter and transaction validation.
					    Database-scoped concurrency lock; index/statistics phase switches;
                        preview mode and heap advisories in place of execution-time heap
                        reporting; selective rowstore discovery; configurable size-sensitive
                        statistics thresholds.
*********************************************************************************************/
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE dbo.spDbMaintenance
	@ReorganizeThreshold		FLOAT = 15,
	@RebuildThreshold			FLOAT = 30,
	@MinPageCount				BIGINT = 1000,
	@MaxRebuildPageCount		BIGINT = NULL,
	@ColumnstoreDeletedPercent	FLOAT = 20,
	@StatsModificationPercent	FLOAT = 10,
	@HeapRebuildEnabled			BIT = 0,
	@HeapForwardedPercent		FLOAT = 10,
	@MaxDurationMinutes			INT = NULL,
	@LockTimeoutSeconds            INT = 60,
    @IndexRebuildEnabled            BIT = 1,
    @StatisticsRebuildEnabled       BIT = 1,
    @PreviewMode                    BIT = 0,
    @StatsSizeSensitiveEnabled       BIT = 1,
    @StatsSizeThresholdFactor        FLOAT = 1000,
    @StatsMinimumModificationCount   BIGINT = 500
AS
BEGIN
	SET NOCOUNT ON;
	SET ANSI_PADDING ON;
    SET ANSI_WARNINGS ON;
    SET ARITHABORT ON;
    SET CONCAT_NULL_YIELDS_NULL ON;
    SET NUMERIC_ROUNDABORT OFF;

    IF @@TRANCOUNT <> 0
        THROW 50001, 'Execute dbo.spDbMaintenance outside a user transaction.', 1;
    IF @ReorganizeThreshold IS NULL OR @ReorganizeThreshold < 0 OR @ReorganizeThreshold > 100
       OR @RebuildThreshold IS NULL OR @RebuildThreshold < @ReorganizeThreshold OR @RebuildThreshold > 100
       OR @ColumnstoreDeletedPercent IS NULL OR @ColumnstoreDeletedPercent < 0 OR @ColumnstoreDeletedPercent > 100
       OR @StatsModificationPercent IS NULL OR @StatsModificationPercent < 0 OR @StatsModificationPercent > 100
       OR @HeapForwardedPercent IS NULL OR @HeapForwardedPercent < 0 OR @HeapForwardedPercent > 100
        THROW 50002, 'Percentages must be 0 through 100; rebuild threshold must be at least reorganize threshold.', 1;
    IF @MinPageCount IS NULL OR @MinPageCount < 0
       OR @MaxRebuildPageCount < 0 OR @MaxDurationMinutes <= 0
       OR @HeapRebuildEnabled IS NULL
       OR @IndexRebuildEnabled IS NULL OR @StatisticsRebuildEnabled IS NULL
       OR @PreviewMode IS NULL OR @StatsSizeSensitiveEnabled IS NULL
       OR @StatsSizeThresholdFactor IS NULL OR @StatsSizeThresholdFactor <= 0
       OR @StatsSizeThresholdFactor > 1.0E100
       OR @StatsMinimumModificationCount IS NULL OR @StatsMinimumModificationCount < 1
       OR @LockTimeoutSeconds IS NULL OR @LockTimeoutSeconds < -1 OR @LockTimeoutSeconds > 2147483
        THROW 50003, 'Invalid limit, phase/preview flag, statistics threshold, or lock timeout.', 1;
    IF CONVERT(nvarchar(60), DATABASEPROPERTYEX(DB_NAME(), 'Updateability')) <> N'READ_WRITE'
        THROW 50004, 'Maintenance requires a read-write database.', 1;

	DECLARE @startTime DATETIME2 = SYSDATETIME();
	DECLARE @lockTimeoutMs INT = CASE WHEN @LockTimeoutSeconds < 0 THEN -1 ELSE @LockTimeoutSeconds * 1000 END;

    -- LOCK_TIMEOUT requires a literal. Execute the procedure within the same
    -- dynamic batch as SET so discovery and maintenance inherit the setting.
    -- The inner invocation sees the requested timeout and does not recurse again.
    -- The application lock is acquired only by that inner invocation.
    IF @@LOCK_TIMEOUT <> @lockTimeoutMs
    BEGIN
        DECLARE @timeoutBatch nvarchar(max);
        SET @timeoutBatch = N'SET LOCK_TIMEOUT ' + CONVERT(nvarchar(12), @lockTimeoutMs)
            + N'; EXEC dbo.spDbMaintenance
                @ReorganizeThreshold = @ReorganizeThreshold,
                @RebuildThreshold = @RebuildThreshold,
                @MinPageCount = @MinPageCount,
                @MaxRebuildPageCount = @MaxRebuildPageCount,
                @ColumnstoreDeletedPercent = @ColumnstoreDeletedPercent,
                @StatsModificationPercent = @StatsModificationPercent,
                @HeapRebuildEnabled = @HeapRebuildEnabled,
                @HeapForwardedPercent = @HeapForwardedPercent,
                @MaxDurationMinutes = @MaxDurationMinutes,
                @LockTimeoutSeconds = @LockTimeoutSeconds,
                @IndexRebuildEnabled = @IndexRebuildEnabled,
                @StatisticsRebuildEnabled = @StatisticsRebuildEnabled,
                @PreviewMode = @PreviewMode,
                @StatsSizeSensitiveEnabled = @StatsSizeSensitiveEnabled,
                @StatsSizeThresholdFactor = @StatsSizeThresholdFactor,
                @StatsMinimumModificationCount = @StatsMinimumModificationCount;';
        EXEC sys.sp_executesql @timeoutBatch,
            N'@ReorganizeThreshold float, @RebuildThreshold float, @MinPageCount bigint, @MaxRebuildPageCount bigint, @ColumnstoreDeletedPercent float, @StatsModificationPercent float, @HeapRebuildEnabled bit, @HeapForwardedPercent float, @MaxDurationMinutes int, @LockTimeoutSeconds int, @IndexRebuildEnabled bit, @StatisticsRebuildEnabled bit, @PreviewMode bit, @StatsSizeSensitiveEnabled bit, @StatsSizeThresholdFactor float, @StatsMinimumModificationCount bigint',
            @ReorganizeThreshold = @ReorganizeThreshold,
            @RebuildThreshold = @RebuildThreshold,
            @MinPageCount = @MinPageCount,
            @MaxRebuildPageCount = @MaxRebuildPageCount,
            @ColumnstoreDeletedPercent = @ColumnstoreDeletedPercent,
            @StatsModificationPercent = @StatsModificationPercent,
            @HeapRebuildEnabled = @HeapRebuildEnabled,
            @HeapForwardedPercent = @HeapForwardedPercent,
            @MaxDurationMinutes = @MaxDurationMinutes,
            @LockTimeoutSeconds = @LockTimeoutSeconds,
            @IndexRebuildEnabled = @IndexRebuildEnabled,
            @StatisticsRebuildEnabled = @StatisticsRebuildEnabled,
            @PreviewMode = @PreviewMode,
            @StatsSizeSensitiveEnabled = @StatsSizeSensitiveEnabled,
            @StatsSizeThresholdFactor = @StatsSizeThresholdFactor,
            @StatsMinimumModificationCount = @StatsMinimumModificationCount;
        RETURN;
    END;

	DECLARE @statement NVARCHAR(MAX);
    DECLARE @workId INT, @objectId INT, @indexId INT;
    DECLARE @schemaName SYSNAME, @objectName SYSNAME, @indexName SYSNAME;
    DECLARE @partitionNumber INT, @metric FLOAT;
    DECLARE @succeeded INT = 0, @skipped INT = 0;
	DECLARE @phase TINYINT;
	DECLARE @lastPhase TINYINT = 0;
	DECLARE @action VARCHAR(10);
	DECLARE @timeUp BIT = 0;
	DECLARE @errors INT = 0;
	DECLARE @message NVARCHAR(4000);

    -- Session ownership avoids holding a transaction across maintenance operations.
    -- Resource locks are scoped to this database and the public database principal.
    DECLARE @appLockResult INT, @releaseResult INT;
    EXEC @appLockResult = sys.sp_getapplock
        @Resource = N'dbo.spDbMaintenance', @LockMode = 'Exclusive',
        @LockOwner = 'Session', @LockTimeout = 0, @DbPrincipal = 'public';
    IF @appLockResult < 0
        THROW 50006, 'Maintenance lock unavailable: another run may already be active.', 1;

    BEGIN TRY

	PRINT 'Script started at '+CONVERT(NVARCHAR(256),GetDate(),113);

	------------------------------------------------------------------------------------------
	-- WORK TABLE: every row is a T-SQL statement to be executed by the single cursor below
	-- Phase 1 = heaps, Phase 2 = indexes, Phase 3 = statistics
	-- Action: REBUILD / REORGANIZE / UPDATE, or REPORT (preview advisory / index skip)
	-- The table is created by the SELECT ... INTO of phase 1: the column types are inferred from
	-- the expressions of that SELECT, so every column is explicitly CAST to the type it must have
	-- also for the INSERTs of phases 2 and 3 (e.g. Action must be VARCHAR(10), not VARCHAR(7)).
	------------------------------------------------------------------------------------------

	------------------------------------------------------------------------------------------
	-- PHASE 1 - HEAPS
	-- Heaps cannot be maintained with ALTER INDEX, the only way is ALTER TABLE ... REBUILD (offline).
	-- Forwarded records are returned only in SAMPLED mode, which is more expensive than LIMITED:
	-- for this reason only the heaps having at least @MinPageCount pages are scanned.
	-- Only the heaps over the forwarded records threshold are kept: they are the ones requiring attention.
	-- Preview exposes heap advisories; execution does not print heap attention reports.
	------------------------------------------------------------------------------------------
	SELECT
		IDENTITY(INT,1,1)										AS WorkId,
		CAST(1 AS TINYINT)										AS Phase,
		CAST(S.[name] AS SYSNAME)								AS SchemaName,
		CAST(O.[name] AS SYSNAME)								AS ObjectName,
		CAST(NULL AS SYSNAME)									AS IndexName,
		CAST(O.object_id AS INT)								AS ObjectId,
		CAST(0 AS INT)											AS IndexId,			-- 0 for heaps, stats_id for statistics
		CAST(0 AS TINYINT)										AS IndexType,
		CAST(CASE WHEN DS.[type] = 'PS' THEN PS.partition_number END AS INT) AS PartitionNumber,	-- NULL = whole object
		CAST(PS.in_row_data_page_count AS BIGINT)				AS PageCount,
		CAST(X.record_count AS BIGINT)							AS RecordCount,		-- heaps only
		CAST(X.forwarded_record_count AS BIGINT)				AS ForwardedRecords,-- heaps only
		CAST(X.avg_page_space_used_in_percent AS FLOAT)			AS PageDensity,		-- heaps only
		CAST(X.forwarded_record_count * 100.0 / NULLIF(X.record_count, 0) AS FLOAT) AS Metric,	-- fragmentation % (rowstore), deleted rows % (columnstore), forwarded records % (heap)
		CAST(CASE
				WHEN @HeapRebuildEnabled = 1 AND (@MaxRebuildPageCount IS NULL OR PS.in_row_data_page_count <= @MaxRebuildPageCount) THEN 'REBUILD'
				ELSE 'REPORT'
			 END AS VARCHAR(10))								AS Action,
		CAST(NULL AS NVARCHAR(MAX)) AS Statement,
        CAST(0 AS BIT) AS Succeeded
	INTO #Work
	FROM sys.dm_db_partition_stats PS
	INNER JOIN sys.objects O ON O.object_id = PS.object_id AND O.[type] = 'U' AND O.is_ms_shipped = 0
	INNER JOIN sys.schemas S ON S.schema_id = O.schema_id
	INNER JOIN sys.indexes I ON I.object_id = PS.object_id AND I.index_id = 0
	INNER JOIN sys.data_spaces DS ON DS.data_space_id = I.data_space_id
	CROSS APPLY sys.dm_db_index_physical_stats(DB_ID(), PS.object_id, 0, PS.partition_number, 'SAMPLED') X
	WHERE (@HeapRebuildEnabled = 1 OR @PreviewMode = 1)
          AND PS.index_id = 0
		  AND PS.in_row_data_page_count >= @MinPageCount
		  AND X.alloc_unit_type_desc = 'IN_ROW_DATA'
		  AND X.forwarded_record_count * 100.0 / NULLIF(X.record_count, 0) >= @HeapForwardedPercent;
		  

	------------------------------------------------------------------------------------------
	-- PHASE 2 - INDEXES
	------------------------------------------------------------------------------------------
	-- Rowstore indexes (clustered and nonclustered) on tables and indexed views
	-- Heaps (handled above), XML, spatial, memory-optimized, disabled and hypothetical indexes are skipped on purpose
    -- SELECT INTO does not create a default for later INSERT statements.
    ALTER TABLE #Work ADD DEFAULT (0) FOR Succeeded;
    IF @IndexRebuildEnabled = 1
    BEGIN
    -- Materialize the metadata filter BEFORE calling the physical-stats function.
    -- Only eligible rowstore partitions receive a targeted LIMITED inspection.
    SELECT PS.object_id, PS.index_id, PS.partition_number
    INTO #RowstoreCandidates
    FROM sys.dm_db_partition_stats PS
    JOIN sys.indexes I ON I.object_id = PS.object_id AND I.index_id = PS.index_id
    JOIN sys.objects O ON O.object_id = I.object_id
    LEFT JOIN sys.tables T ON T.object_id = I.object_id
    WHERE O.[type] IN ('U','V') AND O.is_ms_shipped = 0
      AND I.[type] IN (1,2) AND I.is_disabled = 0 AND I.is_hypothetical = 0
      AND ISNULL(T.is_memory_optimized, 0) = 0
      AND PS.in_row_data_page_count >= @MinPageCount;

	-- Retain index work independently: heap rebuilds may fail, and partition numbers do not prove alignment.
	INSERT INTO #Work (Phase, SchemaName, ObjectName, IndexName, ObjectId, IndexId, IndexType, PartitionNumber, PageCount, Metric, Action)
	SELECT
		2, S.[name], O.[name], I.[name], I.object_id, I.index_id, I.[type],
		CASE WHEN DS.[type] = 'PS' THEN DDIPS.partition_number END,
		DDIPS.page_count,
		DDIPS.avg_fragmentation_in_percent,
		CASE
			WHEN I.allow_page_locks = 0 AND @MaxRebuildPageCount IS NOT NULL
                 AND DDIPS.page_count > @MaxRebuildPageCount THEN 'REPORT'
            WHEN I.allow_page_locks = 0 THEN 'REBUILD'	-- REORGANIZE requires page locks, so it would fail
			WHEN DDIPS.avg_fragmentation_in_percent >= @RebuildThreshold
				 AND (@MaxRebuildPageCount IS NULL OR DDIPS.page_count <= @MaxRebuildPageCount) THEN 'REBUILD'
			ELSE 'REORGANIZE'
		END
	FROM #RowstoreCandidates C
    CROSS APPLY sys.dm_db_index_physical_stats
        (DB_ID(), C.object_id, C.index_id, C.partition_number, 'LIMITED') AS DDIPS
	INNER JOIN sys.objects O ON O.object_id = DDIPS.object_id AND O.[type] IN ('U','V') AND O.is_ms_shipped = 0
	INNER JOIN sys.schemas S ON S.schema_id = O.schema_id
	INNER JOIN sys.indexes I ON I.object_id = DDIPS.object_id AND I.index_id = DDIPS.index_id
	INNER JOIN sys.data_spaces DS ON DS.data_space_id = I.data_space_id
	WHERE I.[type] IN (1,2)
		  AND I.is_disabled = 0			-- REBUILD would silently re-enable a disabled index
		  AND I.is_hypothetical = 0
		  AND DDIPS.index_level = 0
		  AND DDIPS.alloc_unit_type_desc = 'IN_ROW_DATA'
		  AND DDIPS.avg_fragmentation_in_percent >= @ReorganizeThreshold
		  AND DDIPS.page_count >= @MinPageCount;

	-- Columnstore indexes (clustered and nonclustered): fragmentation is measured with deleted rows
	-- Only REORGANIZE is used because it is online and merges rowgroups having many deleted rows
	INSERT INTO #Work (Phase, SchemaName, ObjectName, IndexName, ObjectId, IndexId, IndexType, PartitionNumber, Metric, Action)
	SELECT
		2, S.[name], O.[name], I.[name], I.object_id, I.index_id, I.[type],
		CASE WHEN DS.[type] = 'PS' THEN CS.partition_number END,
		SUM(CS.deleted_rows) * 100.0 / NULLIF(SUM(CS.total_rows), 0),
		'REORGANIZE'
	FROM sys.dm_db_column_store_row_group_physical_stats AS CS
	INNER JOIN sys.objects O ON O.object_id = CS.object_id AND O.[type] IN ('U','V') AND O.is_ms_shipped = 0
	INNER JOIN sys.schemas S ON S.schema_id = O.schema_id
	INNER JOIN sys.indexes I ON I.object_id = CS.object_id AND I.index_id = CS.index_id
	INNER JOIN sys.data_spaces DS ON DS.data_space_id = I.data_space_id
	WHERE I.[type] IN (5,6)
          AND CS.state = 3 -- compressed rowgroups only
		  AND I.is_disabled = 0
		  AND I.is_hypothetical = 0
	GROUP BY S.[name], O.[name], I.[name], I.object_id, I.index_id, I.[type], DS.[type], CS.partition_number
	HAVING SUM(CS.deleted_rows) * 100.0 / NULLIF(SUM(CS.total_rows), 0) >= @ColumnstoreDeletedPercent;

    END; -- @IndexRebuildEnabled

	-- Build the statements (QUOTENAME protects against special characters in names)
	UPDATE #Work
	SET Statement = 'ALTER INDEX ' + QUOTENAME(IndexName) + ' ON ' + QUOTENAME(SchemaName) + '.' + QUOTENAME(ObjectName)
					+ ' ' + Action
					+ CASE WHEN PartitionNumber IS NOT NULL THEN ' PARTITION = ' + CAST(PartitionNumber AS NVARCHAR(10)) ELSE '' END
	WHERE Phase = 2 AND Action <> 'REPORT';

    UPDATE #Work
    SET Statement = N'ALTER TABLE ' + QUOTENAME(SchemaName) + N'.' + QUOTENAME(ObjectName)
        + N' REBUILD' + CASE WHEN PartitionNumber IS NOT NULL
            THEN N' PARTITION = ' + CONVERT(nvarchar(10), PartitionNumber) ELSE N'' END
    WHERE Phase = 1 AND Action = 'REBUILD';

	------------------------------------------------------------------------------------------
	-- PHASE 3 - STATISTICS
    -- Queue eligible statistics without assuming planned rebuilds will succeed.
    -- Eligibility is rechecked immediately before execution.
    ALTER TABLE #Work ADD StatsRows BIGINT NULL, ModificationCount BIGINT NULL,
        ModificationThreshold FLOAT NULL;
    IF @StatisticsRebuildEnabled = 1
    BEGIN
    INSERT INTO #Work (Phase, SchemaName, ObjectName, IndexName, ObjectId, IndexId, Metric, Action, Statement,
                       StatsRows, ModificationCount, ModificationThreshold)
	SELECT
		3, S.[name], O.[name], ST.[name], ST.object_id, ST.stats_id, 0, 'UPDATE',
		'UPDATE STATISTICS ' + QUOTENAME(S.[name]) + '.' + QUOTENAME(O.[name]) + ' ' + QUOTENAME(ST.[name]),
        SP.[rows], SP.modification_counter, ST3.ModificationThreshold
	FROM sys.stats ST
	INNER JOIN sys.objects O ON O.object_id = ST.object_id AND O.[type] IN ('U','V') AND O.is_ms_shipped = 0
	INNER JOIN sys.schemas S ON S.schema_id = O.schema_id
	LEFT JOIN sys.tables T ON T.object_id = O.object_id
	LEFT JOIN sys.indexes I ON I.object_id = ST.object_id AND I.index_id = ST.stats_id	-- only for index statistics
	OUTER APPLY sys.dm_db_stats_properties(ST.object_id, ST.stats_id) SP
    CROSS APPLY (SELECT CONVERT(float, SP.[rows]) * @StatsModificationPercent / 100.0 AS PercentThreshold,
                        SQRT(@StatsSizeThresholdFactor * CONVERT(float, SP.[rows])) AS SizeThreshold) ST1
    CROSS APPLY (SELECT CASE WHEN ST1.SizeThreshold < @StatsMinimumModificationCount
                             THEN CONVERT(float, @StatsMinimumModificationCount)
                             ELSE ST1.SizeThreshold END AS SizeThreshold) ST2
    CROSS APPLY (SELECT CASE WHEN @StatsSizeSensitiveEnabled = 1
                                  AND ST2.SizeThreshold < ST1.PercentThreshold
                             THEN ST2.SizeThreshold ELSE ST1.PercentThreshold END AS ModificationThreshold) ST3
	WHERE ST.is_temporary = 0
		  AND ISNULL(T.is_memory_optimized, 0) = 0
		  AND ISNULL(I.is_disabled, 0) = 0
		  AND ISNULL(I.is_hypothetical, 0) = 0
          AND ((SP.last_updated IS NULL AND EXISTS
                    (SELECT 1 FROM sys.partitions P
                     WHERE P.object_id = ST.object_id AND P.index_id IN (0, 1)
                       AND P.[rows] > 0)) OR (SP.last_updated IS NOT NULL AND SP.modification_counter > 0
               AND (SP.[rows] = 0 OR CONVERT(float, SP.modification_counter) >= ST3.ModificationThreshold)));

    END; -- @StatisticsRebuildEnabled

    IF @PreviewMode = 1
    BEGIN
        SELECT Phase, SchemaName, ObjectName, IndexName, PartitionNumber,
               PageCount, Metric, StatsRows, ModificationCount, ModificationThreshold,
               Action, Statement,
               CASE WHEN Phase = 1 AND @HeapRebuildEnabled = 0 THEN N'Heap rebuilding disabled'
                    WHEN Action = 'REPORT' THEN N'Rebuild page limit exceeded; no permitted fallback'
                    WHEN Phase = 1 THEN N'Forwarded-record threshold reached'
                    WHEN Phase = 2 AND IndexType IN (5,6) THEN N'Columnstore deleted-row threshold reached'
                    WHEN Phase = 2 THEN N'Rowstore fragmentation threshold reached'
                    ELSE N'Statistics uninitialized or modification threshold reached' END AS SelectionReason
        FROM #Work
        ORDER BY Phase, SchemaName, ObjectName,
                 CASE WHEN IndexType IN (1,5) THEN 1 ELSE 2 END, Metric DESC, WorkId;
        EXEC @releaseResult = sys.sp_releaseapplock
            @Resource = N'dbo.spDbMaintenance', @LockOwner = 'Session', @DbPrincipal = 'public';
        RETURN;
    END;

	------------------------------------------------------------------------------------------
	-- EXECUTION: a single cursor runs all the statements in phase order
	------------------------------------------------------------------------------------------
    DECLARE work_cursor CURSOR LOCAL FAST_FORWARD FOR
    SELECT WorkId, Phase, Action, Statement, ObjectId, IndexId,
           SchemaName, ObjectName, IndexName, PartitionNumber, Metric
    FROM #Work
    WHERE NOT (Phase = 1 AND Action = 'REPORT')
    ORDER BY Phase, SchemaName, ObjectName,
             CASE WHEN IndexType IN (1,5) THEN 1 ELSE 2 END, Metric DESC, WorkId;

    OPEN work_cursor;
    FETCH NEXT FROM work_cursor INTO @workId, @phase, @action, @statement,
        @objectId, @indexId, @schemaName, @objectName, @indexName, @partitionNumber, @metric;
    WHILE @@FETCH_STATUS = 0
    BEGIN
        IF @phase <> @lastPhase
        BEGIN
            PRINT CHAR(13) + CASE @phase WHEN 1 THEN 'Checking heaps...'
                WHEN 2 THEN 'Updating indexes...' ELSE 'Updating statistics...' END;
            SET @lastPhase = @phase;
        END;

        IF @action = 'REPORT'
        BEGIN
            SET @skipped += 1;
            IF @phase = 2
                PRINT N'Skipped: page locks are disabled and rebuilding would exceed the page limit.';
        END
        ELSE IF @MaxDurationMinutes IS NOT NULL
            AND DATEDIFF_BIG(SECOND, @startTime, SYSDATETIME()) >= CONVERT(bigint, @MaxDurationMinutes) * 60
        BEGIN
            IF @timeUp = 0
                PRINT N'Maximum duration reached; remaining maintenance commands are skipped.';
            SET @timeUp = 1;
            SET @skipped += 1;
        END
        ELSE
        BEGIN
            BEGIN TRY
                IF @phase = 3 AND
                (
                    EXISTS (SELECT 1 FROM #Work W
                            WHERE W.Phase = 2 AND W.ObjectId = @objectId AND W.IndexId = @indexId
                              AND W.IndexType IN (1,2) AND W.Action = 'REBUILD'
                              AND W.PartitionNumber IS NULL AND W.Succeeded = 1)
                    OR
                    (
                        NOT EXISTS (SELECT 1 FROM sys.dm_db_stats_properties(@objectId, @indexId) SP
                                    WHERE SP.last_updated IS NOT NULL)
                        AND NOT EXISTS (SELECT 1 FROM sys.partitions P
                                        WHERE P.object_id = @objectId AND P.index_id IN (0, 1)
                                          AND P.[rows] > 0)
                    )
                    OR EXISTS (SELECT 1 FROM sys.dm_db_stats_properties(@objectId, @indexId) SP
    CROSS APPLY (SELECT CONVERT(float, SP.[rows]) * @StatsModificationPercent / 100.0 AS PercentThreshold,
                        SQRT(@StatsSizeThresholdFactor * CONVERT(float, SP.[rows])) AS SizeThreshold) ST1
    CROSS APPLY (SELECT CASE WHEN ST1.SizeThreshold < @StatsMinimumModificationCount
                             THEN CONVERT(float, @StatsMinimumModificationCount)
                             ELSE ST1.SizeThreshold END AS SizeThreshold) ST2
    CROSS APPLY (SELECT CASE WHEN @StatsSizeSensitiveEnabled = 1
                                  AND ST2.SizeThreshold < ST1.PercentThreshold
                             THEN ST2.SizeThreshold ELSE ST1.PercentThreshold END AS ModificationThreshold) ST3
                               WHERE SP.last_updated IS NOT NULL
                                 AND (SP.modification_counter = 0
                                      OR (SP.[rows] > 0 AND CONVERT(float, SP.modification_counter) < ST3.ModificationThreshold)))
                )
                BEGIN
                    PRINT N'Skipping statistics: empty and uninitialized, already refreshed, or below threshold: ' + @statement;
                    SET @skipped += 1;
                END
                ELSE
                BEGIN
                    IF @statement IS NULL
                        THROW 50005, 'Internal error: maintenance command is missing.', 1;
                    PRINT N'Executing ' + @statement;
                    EXEC sys.sp_executesql @stmt = @statement;
                    UPDATE #Work SET Succeeded = 1 WHERE WorkId = @workId;
                    SET @succeeded += 1;
                END;
            END TRY
            BEGIN CATCH
                SET @errors += 1;
                PRINT N'ERROR (' + CONVERT(nvarchar(10), ERROR_NUMBER()) + N') on ['
                    + COALESCE(@statement, N'<missing command>') + N']: ' + ERROR_MESSAGE();
            END CATCH;
        END;

        FETCH NEXT FROM work_cursor INTO @workId, @phase, @action, @statement,
            @objectId, @indexId, @schemaName, @objectName, @indexName, @partitionNumber, @metric;
    END;
    CLOSE work_cursor;
    DEALLOCATE work_cursor;

    PRINT N'Completed: ' + CONVERT(nvarchar(20), @succeeded)
        + N'; skipped: ' + CONVERT(nvarchar(20), @skipped)
        + N'; failed: ' + CONVERT(nvarchar(20), @errors) + N'.';
    PRINT N'Script ended at ' + CONVERT(nvarchar(30), SYSDATETIME(), 113);

    -- SET options changed inside a stored procedure revert on return to the caller.
    IF @errors > 0
    BEGIN
        SET @message = N'spDbMaintenance completed with ' + CONVERT(nvarchar(10), @errors)
            + N' error(s); see the execution output for details.';
        THROW 50000, @message, 1;
    END;
    EXEC @releaseResult = sys.sp_releaseapplock
        @Resource = N'dbo.spDbMaintenance', @LockOwner = 'Session', @DbPrincipal = 'public';
    END TRY
    BEGIN CATCH
        EXEC @releaseResult = sys.sp_releaseapplock
            @Resource = N'dbo.spDbMaintenance', @LockOwner = 'Session', @DbPrincipal = 'public';
        THROW;
    END CATCH;
END;
GO