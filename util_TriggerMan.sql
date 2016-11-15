/****** Object:  StoredProcedure [util_TriggerMan]    Script Date: 12/07/2015 09:16:19 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- =============================================
-- Author:		Chad Roesler
-- Create date: 06-07-2013
-- Rev date:	12-07-2015
-- Description:	Auto Generation of triggers
-- =============================================
/***********************************************
EXEC util_TriggerMan SEARCHUSER, null, DEFAULT, 0, 30, 0
***********************************************/
----------------------------
-- Modification:
-- Modified By: Chad Roesler
-- Ticket Number: CR-000031
-- Modification Details: Made self sufficent, added multiple things
-- Modification: This line needed for parsing reason
----------------------------
-- Modification:
-- Modified By: Chad Roesler
-- Ticket Number: CR-000031
-- Modification Details: Added return under drop trigger to prevent errors
-- Modification: This line needed for parsing reason
----------------------------
-- Modification:
-- Modified By: Chad Roesler
-- Ticket Number: CR-000031
-- Modification Details: Initial Creation
-- Modification: This line needed for parsing reason
----------------------------
ALTER PROCEDURE [dbo].[util_TriggerMan]
	(
	@TableName VARCHAR(MAX),
	@PKColumn VARCHAR(MAX) = NULL,
	@ExcludedDataTypes VARCHAR(MAX) = 'IMAGE,XML,VARBINARY,TEXT,NTEXT,BINARY',
	@IncludeDBCC BIT = 1,
	@SelfDestructDays INT = 30,
	@AutoExec BIT = 0
	)
AS
BEGIN
	SET NOCOUNT ON;
	BEGIN TRY
-- =============================================
-- Declaration of Variables
-- =============================================
		DECLARE	@ErrorMessage VARCHAR(MAX)	--ErrorMessage
		DECLARE	@ErrorSeverity INT			--ErrorSeverity
		DECLARE	@Count INT					--Count For While Looping
		DECLARE	@Row INT					--RowID For While Looping
		DECLARE	@CharIndex INT				--Splitting Excluded DataTypes
		DECLARE	@SplitDataType VARCHAR(MAX)	--DataType Split out
		DECLARE	@PriKey VARCHAR(MAX)		--PrimaryKey
		DECLARE	@PriKeyDataType VARCHAR(MAX)--PrimaryKey DataType
		DECLARE	@ColumnName VARCHAR(MAX)	--Current Column Called in While Loop
		DECLARE	@ColumnDataType VARCHAR(MAX)--Current Column DataType called in While Loop
		DECLARE	@AuditTableName	VARCHAR(MAX)--AuditTableName
		DECLARE	@SQLCrTbl VARCHAR(MAX)		--Creation for Audit Table
		DECLARE	@SQLTrgHdr VARCHAR(MAX)		--TriggerHeader
		DECLARE	@SQLSlfDstrct VARCHAR(MAX)	--Trigger Self DestructMethod
		DECLARE	@SQLVarDec VARCHAR(MAX)		--Trigger Variable Declaration
		DECLARE	@SQLVarSlct VARCHAR(MAX)	--Trigger Variable Selection
		DECLARE	@SQLVarTbl VARCHAR(MAX)		--Trigger Variable Table work for gathering SQL Passed
		DECLARE	@SQLUpHdr VARCHAR(MAX)		--Trigger Update Header
		DECLARE	@SQLUpCol VARCHAR(MAX) = ''	--Trigger Update Column Selection
		DECLARE	@SQLUpEnd VARCHAR(MAX)		--Trigger Update End
		DECLARE	@SQLDelHdr VARCHAR(MAX)		--Trigger Delete Header
		DECLARE	@SQLDelCl VARCHAR(MAX)		--Trigger Delete Column Selection
		DECLARE	@SQLDelEnd VARCHAR(MAX)		--Trigger Delete End
		DECLARE	@SQLInsHdr VARCHAR(MAX)		--Trigger Insert Header
		DECLARE	@SQLInsCl VARCHAR(MAX)		--Trigger Insert Column Selection
		DECLARE	@SQLInsEnd VARCHAR(MAX)		--Trigger Insert End
		DECLARE @DBName VARCHAR(MAX)		--Get Current DB Name
		DECLARE @LineStart INT				--Line Start for Printing
		DECLARE	@LineEnd INT				--Line End for Printing
		DECLARE	@LineData VARCHAR(MAX)		--Line Data for Printing

-- =============================================
-- Declaration of Base Variables
-- =============================================
		SELECT	@Row = 2
		SELECT	@PriKey = @PKColumn
		SELECT	@ExcludedDataTypes = NULLIF(RTRIM(LTRIM(@ExcludedDataTypes)),'')
		SELECT	@TableName = t.name
		FROM	sys.tables t
		WHERE	t.name = @TableName
		SELECT	@AuditTableName = @TableName + 'Audit'

-- =============================================
-- Gather DB Name
-- =============================================
		SELECT	@DBName = DB_NAME()

-- =============================================
-- Gather Primary Key
-- =============================================
		IF (NULLIF(RTRIM(LTRIM(@PriKey)),'') IS NULL)
			BEGIN
				SELECT	@PriKey = sc.name
				FROM	sys.indexes si
						INNER JOIN sys.index_columns sic ON sic.object_id = si.object_id
															AND sic.index_id = si.index_id
															AND si.is_primary_key = 1
						INNER JOIN sys.columns sc ON sc.object_id = sic.object_id
													 AND sc.column_id = sic.column_id
						INNER JOIN sys.tables st ON st.object_id = sc.object_id
				WHERE	st.name = @TableName
			END

-- =============================================
-- Error Checking
-- =============================================
		IF (OBJECT_ID(@TableName) IS NULL)
			BEGIN
				SELECT  @ErrorMessage = 'The Table chosen does not exist.  Cannot create Trigger.'
				RAISERROR (@ErrorMessage, 16, 1)
			END
		IF (@PriKey IS NULL)
			BEGIN
				SELECT  @ErrorMessage = 'There is No Primary Key on the Chosen Table.  Cannot create Trigger.'
				RAISERROR (@ErrorMessage, 16, 1)
			END
		IF OBJECT_ID('CUO_TR' + @TableName) IS NOT NULL
			BEGIN
				SELECT  @ErrorMessage = 'A custom Trigger already exists on this table'
				RAISERROR (@ErrorMessage, 16, 1)
			END
		IF OBJECT_ID(@AuditTableName) IS NOT NULL
			BEGIN
				SELECT  @ErrorMessage = 'The Audit table already exists'
				RAISERROR (@ErrorMessage, 16, 1)
			END

-- =============================================
-- Get Primary Key Data Type
-- =============================================
		SELECT	@PriKeyDataType = CASE WHEN ty.name = 'VARCHAR'
									   THEN	ty.name + '(' + CONVERT(VARCHAR(MAX),c.max_length) + ')'
									   WHEN ty.name = 'DECIMAL'
									   THEN ty.name + '(' + CONVERT(VARCHAR(MAX),c.precision) + ',' + CONVERT(VARCHAR(MAX),c.scale) + ')'
									   ELSE ty.name
								  END
		FROM	sys.tables t
				INNER JOIN sys.columns c ON c.object_id = t.object_id
				INNER JOIN sys.types ty ON ty.system_type_id = c.system_type_id
		WHERE	t.name = @TableName
				AND c.name = @PriKey

-- =============================================
-- SplitExcludedColumns
-- =============================================
		CREATE TABLE #ExcludedDataTypes
			(
			DataType VARCHAR(MAX)
			)
		
		IF (@ExcludedDataTypes IS NOT NULL)
			BEGIN
				SELECT	@CharIndex = CHARINDEX(',',@ExcludedDataTypes)
				WHILE (LEN(@ExcludedDataTypes) > 0)
					BEGIN
						IF (@CharIndex = 0)
							BEGIN
								SELECT	@SplitDataType = @ExcludedDataTypes
								SELECT	@ExcludedDataTypes = ''
							END
						ELSE
							BEGIN
								SELECT	@SplitDataType = LEFT(@ExcludedDataTypes, @CharIndex - 1)
								SELECT	@ExcludedDataTypes = RIGHT(@ExcludedDataTypes,LEN(@ExcludedDataTypes) - @CharIndex)
							END
						SELECT	@CharIndex = CHARINDEX(',',@ExcludedDataTypes)
						INSERT INTO #ExcludedDataTypes
							(
							DataType
							)
						SELECT	@SplitDataType
					END
			END

-- =============================================
-- Gather Column Count
-- =============================================
		SELECT 	@Count = COUNT(c.name)
		FROM	sys.tables t
				INNER JOIN sys.columns c ON c.object_id = t.object_id
		WHERE	t.name = @TableName

-- =============================================
-- Dynamic Generation of the Audit Table
-- =============================================
		IF (@IncludeDBCC = 1)
			BEGIN
				SELECT	@SQLCrTbl =	'CREATE TABLE [dbo].[' + @AuditTableName + '](' + (CHAR(13) + CHAR(10)) +
									CHAR(9) + '[AuditID] [int] IDENTITY(1,1) NOT NULL,' + (CHAR(13) + CHAR(10)) +
									CHAR(9) + '[AuditType] [varchar](25) NULL,' + (CHAR(13) + CHAR(10)) +
									CHAR(9) + '[SQLExec] [nvarchar](MAX),' + (CHAR(13) + CHAR(10)) +
									CHAR(9) + '[' + @PriKey + '] [' + @PriKeyDataType + '],' + (CHAR(13) + CHAR(10)) +
									CHAR(9) + '[ColumnName] [varchar](255) NOT NULL,' + (CHAR(13) + CHAR(10)) +
									CHAR(9) + '[OldValue] [varchar](MAX) NULL,' + (CHAR(13) + CHAR(10)) +
									CHAR(9) + '[NewValue] [varchar](MAX) NULL,' + (CHAR(13) + CHAR(10)) +
									CHAR(9) + '[DateModified] [datetime] NOT NULL,' + (CHAR(13) + CHAR(10)) +
									CHAR(9) + '[ModifiedByUserName] [varchar](MAX) NULL)' + (CHAR(13) + CHAR(10))
			END
		ELSE
			BEGIN
				SELECT	@SQLCrTbl =	'CREATE TABLE [dbo].[' + @AuditTableName + '](' + (CHAR(13) + CHAR(10)) +
									CHAR(9) + '[AuditID] [int] IDENTITY(1,1) NOT NULL,' + (CHAR(13) + CHAR(10)) +
									CHAR(9) + '[AuditType] [varchar](25) NULL,' + (CHAR(13) + CHAR(10)) +
									CHAR(9) + '[' + @PriKey + '] [' + @PriKeyDataType + '],' + (CHAR(13) + CHAR(10)) +
									CHAR(9) + '[ColumnName] [varchar](255) NOT NULL,' + (CHAR(13) + CHAR(10)) +
									CHAR(9) + '[OldValue] [varchar](MAX) NULL,' + (CHAR(13) + CHAR(10)) +
									CHAR(9) + '[NewValue] [varchar](MAX) NULL,' + (CHAR(13) + CHAR(10)) +
									CHAR(9) + '[DateModified] [datetime] NOT NULL,' + (CHAR(13) + CHAR(10)) +
									CHAR(9) + '[ModifiedByUserName] [varchar](MAX) NULL)' + (CHAR(13) + CHAR(10))
			END

-- =============================================
-- Trigger Header
-- =============================================
		SELECT	@SQLTrgHdr =	'CREATE TRIGGER [dbo].[CUO_Tr_' + @TableName + '] ON [dbo].[' + @TableName + ']' + (CHAR(13) + CHAR(10)) +
								'FOR INSERT, DELETE, UPDATE' + (CHAR(13) + CHAR(10)) +
								'AS' + (CHAR(13) + CHAR(10)) +
								CHAR(9) + 'SET NOCOUNT ON;' + (CHAR(13) + CHAR(10)) +
								(CHAR(13) + CHAR(10))

-- =============================================
-- Dynamic Generation of the Self Destruct
-- The Trigger will Self Desctruct after 30 days
-- =============================================
		SELECT	@SQLSlfDstrct =	CHAR(9) + 'IF EXISTS (	SELECT' + CHAR(9) + '*' + (CHAR(13) + CHAR(10)) +
								CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + 'FROM' + CHAR(9) + 'sys.triggers st' + (CHAR(13) + CHAR(10)) +
								CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + 'WHERE' + CHAR(9) + 'st.object_id = OBJECT_ID(N''[dbo].[CUO_Tr_' + @TableName + ']'')' + (CHAR(13) + CHAR(10)) +
								CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + 'AND DATEDIFF(dd,st.create_Date,GETDATE()) > ' + CONVERT(VARCHAR(MAX),@SelfDestructDays) + ' )' + (CHAR(13) + CHAR(10)) +
								CHAR(9) + CHAR(9) + 'BEGIN' + (CHAR(13) + CHAR(10)) +
								CHAR(9) + CHAR(9) + CHAR(9) + 'DROP TRIGGER [dbo].[CUO_Tr_' + @TableName + ']' + (CHAR(13) + CHAR(10)) +
								CHAR(9) + CHAR(9) + CHAR(9) + 'RETURN;' + (CHAR(13) + CHAR(10)) +
								CHAR(9) + CHAR(9) + 'END' + (CHAR(13) + CHAR(10)) +
								(CHAR(13) + CHAR(10))
-- =============================================
-- Declaration of Variables for the Trigger
-- =============================================
		IF (@IncludeDBCC = 1)
			BEGIN
				SELECT	@SQLVarDec =	CHAR(9) + 'DECLARE' + CHAR(9) + '@ExecStr VARCHAR(50)' + (CHAR(13) + CHAR(10))
			END
		ELSE
			BEGIN
				SELECT	@SQLVarDec =	''
			END

		SELECT	@SQLVarDec =	@SQLVarDec + 
								CHAR(9) + 'DECLARE' + CHAR(9) + '@UserSQL NVARCHAR(MAX)' + (CHAR(13) + CHAR(10)) +
								CHAR(9) + 'DECLARE' + CHAR(9) + '@UserName VARCHAR(MAX)' + (CHAR(13) + CHAR(10)) +
								CHAR(9) + 'DECLARE' + CHAR(9) + '@Type CHAR(1)' + (CHAR(13) + CHAR(10))
-- =============================================
-- Setting Values of Variables
-- =============================================
		IF (@IncludeDBCC = 1)
			BEGIN
				SELECT	@SQLVarSlct =	CHAR(9) + 'SELECT' + CHAR(9) + '@ExecStr = ''DBCC INPUTBUFFER(@@SPID) with no_infomsgs''' + (CHAR(13) + CHAR(10))
			END
		ELSE
			BEGIN
				SELECT	@SQLVarSlct =	''
			END	
	
		SELECT	@SQLVarSlct =	@SQLVarSlct +
								CHAR(9) + 'SELECT' + CHAR(9) + '@UserName = SYSTEM_USER' + (CHAR(13) + CHAR(10)) +
								CHAR(9) + 'SELECT' + CHAR(9) + '@Type = CASE WHEN NOT EXISTS (' + CHAR(9) + 'SELECT' + CHAR(9) + '*' + (CHAR(13) + CHAR(10)) +
								CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + 'FROM' + CHAR(9) + 'inserted)' + (CHAR(13) + CHAR(10)) +
								CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + ' THEN ''D''' + (CHAR(13) + CHAR(10)) +
								CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + ' WHEN EXISTS (' + CHAR(9) + 'SELECT' + CHAR(9) + '*' + (CHAR(13) + CHAR(10)) +
								CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + 'FROM' + CHAR(9) + 'deleted)' + (CHAR(13) + CHAR(10)) +
								CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + ' THEN ''U''' + (CHAR(13) + CHAR(10)) +
								CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + ' ELSE ''I''' + (CHAR(13) + CHAR(10)) +
								CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + ' END' + (CHAR(13) + CHAR(10)) +
								(CHAR(13) + CHAR(10))

-- =============================================
-- Table Creation for gathering the SQL passed
-- to modify the table
-- =============================================
		IF (@IncludeDBCC = 1)
			BEGIN
				SELECT	@SQLVarTbl =	CHAR(9) + 'CREATE TABLE #InputBuffer' + (CHAR(13) + CHAR(10)) +
										CHAR(9) + CHAR(9) + '(' + (CHAR(13) + CHAR(10)) +
										CHAR(9) + CHAR(9) + 'EventType NVARCHAR(30),' + (CHAR(13) + CHAR(10)) +
										CHAR(9) + CHAR(9) + 'Parameters INT,' + (CHAR(13) + CHAR(10)) +
										CHAR(9) + CHAR(9) + 'EventInfo NVARCHAR(max)' + (CHAR(13) + CHAR(10)) +
										CHAR(9) + CHAR(9) + ')' + (CHAR(13) + CHAR(10)) +
										CHAR(9) + 'INSERT INTO #InputBuffer' + (CHAR(13) + CHAR(10)) +
										CHAR(9) + CHAR(9) + '(' + (CHAR(13) + CHAR(10)) +
										CHAR(9) + CHAR(9) + 'EventType,' + (CHAR(13) + CHAR(10)) +
										CHAR(9) + CHAR(9) + 'Parameters,' + (CHAR(13) + CHAR(10)) +
										CHAR(9) + CHAR(9) + 'EventInfo' + (CHAR(13) + CHAR(10)) +
										CHAR(9) + CHAR(9) + ')' + (CHAR(13) + CHAR(10)) +
										CHAR(9) + 'EXEC (@ExecStr)' + (CHAR(13) + CHAR(10)) +
										(CHAR(13) + CHAR(10)) +
										CHAR(9) + 'SELECT @UserSQL = ib.EventInfo' + (CHAR(13) + CHAR(10)) +
										CHAR(9) + 'FROM #InputBuffer ib' + (CHAR(13) + CHAR(10)) +
										(CHAR(13) + CHAR(10))
			END
		ELSE
			BEGIN
				SELECT @SQLVarTbl =		''
			END
-- =============================================
-- Update Section
-- Pass through 10 for tables with many columns
-- =============================================
		SELECT	@SQLUpHdr =		CHAR(9) + 'IF (@Type = ''U'')' + (CHAR(13) + CHAR(10)) +
								CHAR(9) + CHAR(9) + 'BEGIN' + (CHAR(13) + CHAR(10))

		WHILE (@Row <= (@Count))
			BEGIN
				SELECT	@ColumnName = c.name
				FROM	sys.tables t
						INNER JOIN sys.columns c ON c.object_id = t.object_id
				WHERE	t.name = @TableName
						AND c.column_id = @Row
				IF EXISTS (	SELECT	1
							FROM	sys.tables t
									INNER JOIN sys.columns c ON c.object_id = t.object_id
									INNER JOIN sys.types ty ON ty.system_type_id = c.system_type_id
									INNER JOIN #ExcludedDataTypes edt ON edt.DataType = ty.name
							WHERE	t.name = @TableName
									AND c.name = @ColumnName )
					BEGIN
						SELECT	@Row = @Row + 1
					END
				ELSE
					BEGIN
						IF (@IncludeDBCC = 1)
							BEGIN
								SELECT	@SQLUpCol = @SQLUpCol + CHAR(9) + CHAR(9) + CHAR(9) + 'IF UPDATE(' + @ColumnName + ')' + (CHAR(13) + CHAR(10)) +
													CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + 'BEGIN' + (CHAR(13) + CHAR(10)) +
													CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + 'INSERT INTO ' + @AuditTableName + (CHAR(13) + CHAR(10)) +
													CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + '(' + (CHAR(13) + CHAR(10)) +
													CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + 'ModifiedByUserName,' + (CHAR(13) + CHAR(10)) +
													CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + 'AuditType,' + (CHAR(13) + CHAR(10)) +
													CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + 'SQLExec,' + (CHAR(13) + CHAR(10)) +
													CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + @PriKey + ',' + (CHAR(13) + CHAR(10)) +
													CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + 'ColumnName,' + (CHAR(13) + CHAR(10)) +
													CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + 'OldValue,' + (CHAR(13) + CHAR(10)) +
													CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + 'NewValue,' + (CHAR(13) + CHAR(10)) +
													CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + 'DateModified' + (CHAR(13) + CHAR(10)) +
													CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + ')' + (CHAR(13) + CHAR(10)) +
													CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + 'SELECT' + CHAR(9) + '@UserName,' + (CHAR(13) + CHAR(10)) +
													CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + '''UPDATE'',' + (CHAR(13) + CHAR(10)) +
													CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + '@UserSQL,' + (CHAR(13) + CHAR(10)) +
													CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + 'i.' + @PriKey + ',' + (CHAR(13) + CHAR(10)) +
													CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + '''' + @ColumnName + ''',' + (CHAR(13) + CHAR(10)) +
													CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + 'CONVERT(VARCHAR(MAX),d.' + @ColumnName + '),' + (CHAR(13) + CHAR(10)) +
													CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + 'CONVERT(VARCHAR(MAX),i.' + @ColumnName + '),' + (CHAR(13) + CHAR(10)) +
													CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + 'GETDATE()' + (CHAR(13) + CHAR(10)) +
													CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + 'FROM' + CHAR(9) + 'deleted d' + (CHAR(13) + CHAR(10)) +
													CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + 'INNER JOIN inserted i ON i.' + @PriKey + ' = d.' + @PriKey + (CHAR(13) + CHAR(10)) +
													CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + 'END' + (CHAR(13) + CHAR(10))
							END
						ELSE
							BEGIN
								SELECT	@SQLUpCol = @SQLUpCol + CHAR(9) + CHAR(9) + CHAR(9) + 'IF UPDATE(' + @ColumnName + ')' + (CHAR(13) + CHAR(10)) +
													CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + 'BEGIN' + (CHAR(13) + CHAR(10)) +
													CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + 'INSERT INTO ' + @AuditTableName + (CHAR(13) + CHAR(10)) +
													CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + '(' + (CHAR(13) + CHAR(10)) +
													CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + 'ModifiedByUserName,' + (CHAR(13) + CHAR(10)) +
													CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + 'AuditType,' + (CHAR(13) + CHAR(10)) +
													CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + @PriKey + ',' + (CHAR(13) + CHAR(10)) +
													CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + 'ColumnName,' + (CHAR(13) + CHAR(10)) +
													CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + 'OldValue,' + (CHAR(13) + CHAR(10)) +
													CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + 'NewValue,' + (CHAR(13) + CHAR(10)) +
													CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + 'DateModified' + (CHAR(13) + CHAR(10)) +
													CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + ')' + (CHAR(13) + CHAR(10)) +
													CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + 'SELECT' + CHAR(9) + '@UserName,' + (CHAR(13) + CHAR(10)) +
													CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + '''UPDATE'',' + (CHAR(13) + CHAR(10)) +
													CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + 'i.' + @PriKey + ',' + (CHAR(13) + CHAR(10)) +
													CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + '''' + @ColumnName + ''',' + (CHAR(13) + CHAR(10)) +
													CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + 'CONVERT(VARCHAR(MAX),d.' + @ColumnName + '),' + (CHAR(13) + CHAR(10)) +
													CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + 'CONVERT(VARCHAR(MAX),i.' + @ColumnName + '),' + (CHAR(13) + CHAR(10)) +
													CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + 'GETDATE()' + (CHAR(13) + CHAR(10)) +
													CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + 'FROM' + CHAR(9) + 'deleted d' + (CHAR(13) + CHAR(10)) +
													CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + 'INNER JOIN inserted i ON i.' + @PriKey + ' = d.' + @PriKey + (CHAR(13) + CHAR(10)) +
													CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + 'END' + (CHAR(13) + CHAR(10))
							END
						SELECT	@Row = @Row + 1
					END
			END

		SELECT	@SQLUpEnd =		CHAR(9) + CHAR(9) + 'END' + (CHAR(13) + CHAR(10))

-- =============================================
-- Insert Section
-- =============================================
		SELECT	@SQLInsHdr =	CHAR(9) + 'IF (@Type = ''I'')' + (CHAR(13) + CHAR(10)) +
								CHAR(9) + CHAR(9) + 'BEGIN' + (CHAR(13) + CHAR(10))

		IF (@IncludeDBCC = 1)
			BEGIN
				SELECT	@SQLInsCl =		CHAR(9) + CHAR(9) + CHAR(9) + 'INSERT INTO ' + @AuditTableName + (CHAR(13) + CHAR(10)) +
										CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + '(' + (CHAR(13) + CHAR(10)) +
										CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + 'ModifiedByUserName,' + (CHAR(13) + CHAR(10)) +
										CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + 'AuditType,' + (CHAR(13) + CHAR(10)) +
										CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + 'SQLExec,' + (CHAR(13) + CHAR(10)) +
										CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + @PriKey + ',' + (CHAR(13) + CHAR(10)) +
										CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + 'ColumnName,' + (CHAR(13) + CHAR(10)) +
										CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + 'OldValue,' + (CHAR(13) + CHAR(10)) +
										CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + 'NewValue,' + (CHAR(13) + CHAR(10)) +
										CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + 'DateModified' + (CHAR(13) + CHAR(10)) +
										CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + ')' + (CHAR(13) + CHAR(10)) +
										CHAR(9) + CHAR(9) + CHAR(9) + 'SELECT' + CHAR(9) + '@UserName,' + (CHAR(13) + CHAR(10)) +
										CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + '''INSERT'',' + (CHAR(13) + CHAR(10)) +
										CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + '@UserSQL,' + (CHAR(13) + CHAR(10)) +
										CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + 'i.' + @PriKey + ',' + (CHAR(13) + CHAR(10)) +
										CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + '''' + @PriKey + ''',' + (CHAR(13) + CHAR(10)) +
										CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + 'NULL,' + (CHAR(13) + CHAR(10)) +
										CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + 'CONVERT(VARCHAR(MAX),i.' + @PriKey + '),' + (CHAR(13) + CHAR(10)) +
										CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + 'GETDATE()' + (CHAR(13) + CHAR(10)) +
										CHAR(9) + CHAR(9) + CHAR(9) + 'FROM' + CHAR(9) + 'inserted i' + (CHAR(13) + CHAR(10))
			END
		ELSE
			BEGIN
				SELECT	@SQLInsCl =		CHAR(9) + CHAR(9) + CHAR(9) + 'INSERT INTO ' + @AuditTableName + (CHAR(13) + CHAR(10)) +
										CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + '(' + (CHAR(13) + CHAR(10)) +
										CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + 'ModifiedByUserName,' + (CHAR(13) + CHAR(10)) +
										CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + 'AuditType,' + (CHAR(13) + CHAR(10)) +
										CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + @PriKey + ',' + (CHAR(13) + CHAR(10)) +
										CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + 'ColumnName,' + (CHAR(13) + CHAR(10)) +
										CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + 'OldValue,' + (CHAR(13) + CHAR(10)) +
										CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + 'NewValue,' + (CHAR(13) + CHAR(10)) +
										CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + 'DateModified' + (CHAR(13) + CHAR(10)) +
										CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + ')' + (CHAR(13) + CHAR(10)) +
										CHAR(9) + CHAR(9) + CHAR(9) + 'SELECT' + CHAR(9) + '@UserName,' + (CHAR(13) + CHAR(10)) +
										CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + '''INSERT'',' + (CHAR(13) + CHAR(10)) +
										CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + 'i.' + @PriKey + ',' + (CHAR(13) + CHAR(10)) +
										CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + '''' + @PriKey + ''',' + (CHAR(13) + CHAR(10)) +
										CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + 'NULL,' + (CHAR(13) + CHAR(10)) +
										CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + 'CONVERT(VARCHAR(MAX),i.' + @PriKey + '),' + (CHAR(13) + CHAR(10)) +
										CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + 'GETDATE()' + (CHAR(13) + CHAR(10)) +
										CHAR(9) + CHAR(9) + CHAR(9) + 'FROM' + CHAR(9) + 'inserted i' + (CHAR(13) + CHAR(10))
			END

		SELECT	@SQLInsEnd =	CHAR(9) + CHAR(9) + 'END' + (CHAR(13) + CHAR(10))

-- =============================================
-- Delete Section
-- =============================================
		SELECT	@SQLDelHdr =	CHAR(9) + 'IF (@Type = ''D'')' + (CHAR(13) + CHAR(10)) +
								CHAR(9) + CHAR(9) + 'BEGIN' + (CHAR(13) + CHAR(10))

		IF (@IncludeDBCC = 1)
			BEGIN
				SELECT	@SQLDelCl =		CHAR(9) + CHAR(9) + CHAR(9) + 'INSERT INTO ' + @AuditTableName + (CHAR(13) + CHAR(10)) +
										CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + '(' + (CHAR(13) + CHAR(10)) +
										CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + 'ModifiedByUserName,' + (CHAR(13) + CHAR(10)) +
										CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + 'AuditType,' + (CHAR(13) + CHAR(10)) +
										CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + 'SQLExec,' + (CHAR(13) + CHAR(10)) +
										CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + @PriKey + ',' + (CHAR(13) + CHAR(10)) +
										CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + 'ColumnName,' + (CHAR(13) + CHAR(10)) +
										CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + 'OldValue,' + (CHAR(13) + CHAR(10)) +
										CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + 'NewValue,' + (CHAR(13) + CHAR(10)) +
										CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + 'DateModified' + (CHAR(13) + CHAR(10)) +
										CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + ')' + (CHAR(13) + CHAR(10)) +
										CHAR(9) + CHAR(9) + CHAR(9) + 'SELECT' + CHAR(9) + '@UserName,' + (CHAR(13) + CHAR(10)) +
										CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + '''DELETE'',' + (CHAR(13) + CHAR(10)) +
										CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + '@UserSQL,' + (CHAR(13) + CHAR(10)) +
										CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + 'CONVERT(VARCHAR(MAX),d.' + @PriKey + '),' + (CHAR(13) + CHAR(10)) +
										CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + '''' + @PriKey + ''',' + (CHAR(13) + CHAR(10)) +
										CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + 'd.' + @PriKey + ',' + (CHAR(13) + CHAR(10)) +
										CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + 'NULL,' + (CHAR(13) + CHAR(10)) +
										CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + 'GETDATE()' + (CHAR(13) + CHAR(10)) +
										CHAR(9) + CHAR(9) + CHAR(9) + 'FROM' + CHAR(9) + 'deleted d' + (CHAR(13) + CHAR(10))
			END
		ELSE
			BEGIN
				SELECT	@SQLDelCl =		CHAR(9) + CHAR(9) + CHAR(9) + 'INSERT INTO ' + @AuditTableName + (CHAR(13) + CHAR(10)) +
										CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + '(' + (CHAR(13) + CHAR(10)) +
										CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + 'ModifiedByUserName,' + (CHAR(13) + CHAR(10)) +
										CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + 'AuditType,' + (CHAR(13) + CHAR(10)) +
										CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + @PriKey + ',' + (CHAR(13) + CHAR(10)) +
										CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + 'ColumnName,' + (CHAR(13) + CHAR(10)) +
										CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + 'OldValue,' + (CHAR(13) + CHAR(10)) +
										CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + 'NewValue,' + (CHAR(13) + CHAR(10)) +
										CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + 'DateModified' + (CHAR(13) + CHAR(10)) +
										CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + ')' + (CHAR(13) + CHAR(10)) +
										CHAR(9) + CHAR(9) + CHAR(9) + 'SELECT' + CHAR(9) + '@UserName,' + (CHAR(13) + CHAR(10)) +
										CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + '''DELETE'',' + (CHAR(13) + CHAR(10)) +
										CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + 'CONVERT(VARCHAR(MAX),d.' + @PriKey + '),' + (CHAR(13) + CHAR(10)) +
										CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + '''' + @PriKey + ''',' + (CHAR(13) + CHAR(10)) +
										CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + 'd.' + @PriKey + ',' + (CHAR(13) + CHAR(10)) +
										CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + 'NULL,' + (CHAR(13) + CHAR(10)) +
										CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + 'GETDATE()' + (CHAR(13) + CHAR(10)) +
										CHAR(9) + CHAR(9) + CHAR(9) + 'FROM' + CHAR(9) + 'deleted d' + (CHAR(13) + CHAR(10))
			END

		SELECT	@SQLDelEnd =	CHAR(9) + CHAR(9) + 'END' + (CHAR(13) + CHAR(10))

		IF (@AutoExec = 1)
			BEGIN
				EXEC ( @SQLCrTbl )
				EXEC ( @SQLTrgHdr + @SQLSlfDstrct + @SQLVarDec + @SQLVarSlct + @SQLVarTbl + @SQLUpHdr + @SQLUpCol + @SQLUpEnd + @SQLInsHdr + @SQLInsCl + @SQLInsEnd + @SQLDelHdr + @SQLDelCl + @SQLDelEnd )
			END
-- =============================================
-- Execution of for Creation of table and Trigger
-- =============================================
		ELSE
			BEGIN
				PRINT @SQLCrTbl
				PRINT 'GO'
				PRINT @SQLTrgHdr
				PRINT @SQLSlfDstrct
				PRINT @SQLVarDec
				PRINT @SQLVarSlct
				PRINT @SQLVarTbl
				PRINT @SQLUpHdr

				SELECT	@LineStart = 1

				SELECT	@LineEnd = 8001 - CHARINDEX(CHAR(10),REVERSE(SUBSTRING(@SQLUpCol,@LineStart,8000)))

				SELECT	@LineData = SUBSTRING(@SQLUpCol,@LineStart,@LineEnd)

				WHILE (@LineStart < LEN(@SQLUpCol))
					BEGIN
						PRINT @LineData

						SELECT	@LineStart = @LineStart + @LineEnd

						SELECT	@LineEnd = 8001 - CHARINDEX(CHAR(10),REVERSE(SUBSTRING(@SQLUpCol,@LineStart,8000)))

						SELECT	@LineData = SUBSTRING(@SQLUpCol,@LineStart,@LineEnd)
					END
				PRINT @SQLUpEnd
				PRINT @SQLInsHdr
				PRINT @SQLInsCl
				PRINT @SQLInsEnd
				PRINT @SQLDelHdr
				PRINT @SQLDelCl
				PRINT @SQLDelEnd
			END
	END TRY

	BEGIN CATCH

		IF (@@TRANCOUNT > 0)
			BEGIN
				ROLLBACK
				PRINT 'ERRORS OCCURED NO CHANGES HAVE BEEN MADE'
			END

		SELECT	@ErrorMessage = ERROR_MESSAGE(),
				@ErrorSeverity = ERROR_SEVERITY()
		RAISERROR (@ErrorMessage,@ErrorSeverity,1)
		RETURN 1
	END CATCH
END
