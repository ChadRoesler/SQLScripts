/************************************************************************************
-- Drop/Creation of util_SprocDiff [3]
************************************************************************************/
-- =============================================
-- Author:		Chad Roesler
-- Create date: 07-11-2013
-- Rev date:	08-10-2013
-- Description:	Used for Generating Checksums
-- for either Release or Client Database.
-- This does comment and whitespace removal.
-- Suppress will skip the prints and execs util_ObjOut
-- Output location is now defineable
-- =============================================
/***********************************************
EXEC [util_Devops_ObjDiff] 0, 0, 'C:\Temp', 'Test', 'FN,IF,V,P,TF,TR', 1
***********************************************/
----------------------------
-- Modification:
-- Modified By: Chad Roesler
-- Ticket Number: CR-000039
-- Modification Details: Addition of Use of bcp
-- This is used for the server instance
-- Modification: This line needed for parsing reason
----------------------------
-- Modification:
-- Modified By: Chad Roesler
-- Ticket Number: CR-000039
-- Modification Details: Addition of outputlocation
-- Modification: This line needed for parsing reason
----------------------------
-- Modification:
-- Modified By: Alec Hedlund
-- Ticket Number: CR-000039
-- Modification Details: Addition of Comment Remover
-- Modification: This line needed for parsing reason
----------------------------
-- Modified By: Chad Roesler
-- Ticket Number: CR-000039
-- Modification Details: Initial Creation
-- Modification: This line needed for parsing reason
----------------------------
CREATE PROCEDURE [dbo].[util_Devops_ObjDiff]
	(
	@GenerateForRelease BIT,
	@SuppressOutput BIT = 0,
	@OutputLocation VARCHAR(MAX) = 'C:\Temp',
	@ClientName VARCHAR(MAX) = NULL,
	@Objects VARCHAR(MAX) = 'FN,IF,V,P,TF,TR',
	@BCP BIT = 1
	)
AS
BEGIN
	SET NOCOUNT ON;
	BEGIN TRY

-- =============================================
-- Declaration of Variables
-- =============================================
		DECLARE	@InsertPrint VARCHAR(MAX)
		DECLARE	@SQLExec VARCHAR(MAX)
		DECLARE	@SQLTextCompact VARCHAR(MAX)
		DECLARE	@Marker INT
		DECLARE	@NextLine INT
		DECLARE	@NextBlock INT
		DECLARE	@NextBlockEnd INT
		DECLARE	@StuffStart INT
		DECLARE	@StuffLength INT
		DECLARE	@SDFolderExec VARCHAR(MAX)
		DECLARE	@TypeOutputLocation VARCHAR(MAX)
		DECLARE	@Row INT = 1
		DECLARE	@Count INT
		DECLARE	@ObjType VARCHAR(10)

		
		SELECT	@ClientName = ISNULL(@ClientName,DB_NAME())

-- =============================================
-- Parse Objects for Gathering
-- =============================================
		DECLARE	@ObjectTypes TABLE
			(
			RowID INT IDENTITY (1,1),
			Type VARCHAR(10)
			)
		
		IF (@Objects IS NOT NULL)
			BEGIN
				INSERT INTO @ObjectTypes
					(
					Type
					)
				SELECT	s.Item
				FROM	dbo.split(@Objects,',') s
			END
		
		SELECT	@Count = COUNT(*)
		FROM	@ObjectTypes ot

-- =============================================
-- Error Check
-- =============================================
		DECLARE @ErrorMessage VARCHAR(MAX)
		DECLARE	@Run BIT

		DECLARE @cmdshellCheck TABLE
			(
			Name VARCHAR(MAX),
			Minimum BIT,
			Maximum BIT,
			Config_Value BIT,
			Run_Value BIT
			)

		DECLARE	@FolderExistence TABLE
			(
			Exist VARCHAR(MAX)
			)

		DECLARE	@SPFolder TABLE
			(
			Errors VARCHAR(MAX)
			)

		IF (SUBSTRING(REVERSE(@OutputLocation),1,1) <> '\')
			BEGIN
				SELECT	@OutputLocation = @OutputLocation + '\' + @ClientName + '_ObjDiff' + '\'
			END
		ELSE
			BEGIN
				SELECT	@OutputLocation = @OutputLocation + @ClientName + '_ObjDiff' + '\'
			END

		SELECT	@SDFolderExec = 'master.dbo.xp_cmdshell ''MD "' + @OutputLocation + '"'''

		IF (OBJECT_ID('util_ObjOut') IS NULL)
			BEGIN
				SELECT  @ErrorMessage = 'util_ObjOut does not exist.' + CHAR(13) + CHAR(10) +
										'Please create this procedure for this Database.'
				RAISERROR (@ErrorMessage, 16, 1)
			END
		IF (@GenerateForRelease = 1)
			BEGIN
				IF (OBJECT_ID('dbo.AdminObjChecksum') IS NULL)
					BEGIN
						CREATE TABLE dbo.AdminObjChecksum
							(
							AdminObjChecksumID INT IDENTITY (1,1),
							ObjectName VARCHAR(500),
							ObjectType VARCHAR(10),
							ClientDBChecksum BIGINT,
							ReleaseDBChecksum BIGINT
							)
						CREATE NONCLUSTERED INDEX IX_AOC_AOCON
							ON dbo.AdminObjChecksum
								(ObjectName)
						CREATE NONCLUSTERED INDEX IX_AOC_AOCOT
							ON dbo.AdminObjChecksum
								(ObjectType)
					END
			END--@GenerateForRelease = 1
		ELSE--@GenerateForRelease = 0
			BEGIN
				IF (OBJECT_ID('dbo.AdminObjChecksum') IS NULL)
					BEGIN
						SELECT  @ErrorMessage = 'AdminObjChecksum Table does not exist.' + CHAR(13) + CHAR(10) +
												'Please run SprocDiffing.sql to create the table and Insert the Release Checksums.'
						RAISERROR (@ErrorMessage, 16, 1)
					END
				ELSE
					BEGIN
						IF NOT EXISTS (	SELECT	i.name
										FROM	sys.objects o
												INNER JOIN sys.indexes i ON i.object_id = o.object_id
										WHERE	o.name = 'AdminObjChecksum'
												AND i.name = 'IX_AOC_AOCON')
							BEGIN
								CREATE NONCLUSTERED INDEX IX_AOC_AOCON
									ON dbo.AdminObjChecksum
										(ObjectName)
							END
						IF NOT EXISTS (	SELECT	i.name
										FROM	sys.objects o
												INNER JOIN sys.indexes i ON i.object_id = o.object_id
										WHERE	o.name = 'AdminObjChecksum'
												AND i.name = 'IX_AOC_AOCOT')
							BEGIN
								CREATE NONCLUSTERED INDEX IX_AOC_AOCON
									ON dbo.AdminObjChecksum
										(ObjectType)
							END
					END

				IF EXISTS (	SELECT	*
							FROM	AdminObjChecksum aoc
							WHERE	aoc.ReleaseDBChecksum IS NULL )
					BEGIN
						SELECT  @ErrorMessage = 'ReleaseDBChecksum column has nulls.' + CHAR(13) + CHAR(10) +
												'Please run SprocDiffing.sql to create the table and Insert the Release Checksums.'
						RAISERROR (@ErrorMessage, 16, 1)
					END

				INSERT @cmdshellCheck
					(
					Name,
					Minimum,
					Maximum,
					Config_Value,
					Run_Value
					)
				EXEC master.dbo.sp_configure [xp_cmdshell]

				SELECT	@Run = cc.Run_Value
				FROM	@cmdshellCheck cc

				IF (@Run = 0)
					BEGIN
						SELECT	@ErrorMessage = 'xp_cmdshell is not configured on the server please enable xp_cmdshell.'
						RAISERROR ( @ErrorMessage, 16, 1 )

					END--@Run = 0
				ELSE--@Run = 1
					BEGIN
						INSERT @FolderExistence
							(
							Exist
							)
						EXEC ('master.dbo.xp_cmdshell ''if exist "' + @OutputLocation + '" (echo 1) ELSE (echo 0)''')

						IF EXISTS (	SELECT	*
									FROM	@FolderExistence fe
									WHERE	fe.Exist NOT IN ('0', '1')
											AND fe.Exist IS NOT NULL )
							BEGIN
								SELECT	*
								FROM	@FolderExistence fe
								WHERE	fe.Exist NOT IN ('0', '1')
										AND fe.Exist IS NOT NULL

								SELECT	@ErrorMessage = 'Errors have occured when attempting to verify the following location: ' + @OutputLocation + '.' + CHAR(13) + CHAR(10) +
														'Please review the provided information.'
								RAISERROR ( @ErrorMessage, 16, 1 )

							END

						IF EXISTS ( SELECT	*
									FROM	@FolderExistence fe
									WHERE	fe.Exist = 0 )
							BEGIN
								INSERT @SPFolder
									(
									Errors
									)
								EXEC (@SDFolderExec)

								IF EXISTS (	SELECT	*
											FROM	@SPFolder spf
											WHERE	spf.Errors IS NOT NULL )
									BEGIN
										SELECT	@ErrorMessage = 'Errors have occured when attempting to create the following location: ' + @OutputLocation + '.' + CHAR(13) + CHAR(10) +
																'Please review the provided information.'
										RAISERROR ( @ErrorMessage, 16, 1 )
									END
							END
						WHILE @Count >= @Row
							BEGIN
								SELECT	@ObjType = ot.Type
								FROM	@ObjectTypes ot
								WHERE	ot.RowID = @Row

								SELECT	@Row = @Row + 1

								SELECT	@TypeOutputLocation = @OutputLocation + @ObjType + '\'

								SELECT	@SDFolderExec = 'master.dbo.xp_cmdshell ''MD "' + @TypeOutputLocation + '"'''

								INSERT @FolderExistence
									(
									Exist
									)
								EXEC ('master.dbo.xp_cmdshell ''if exist "' + @TypeOutputLocation + '" (echo 1) ELSE (echo 0)''')

								IF EXISTS (	SELECT	*
											FROM	@FolderExistence fe
											WHERE	fe.Exist NOT IN ('0', '1')
													AND fe.Exist IS NOT NULL )
									BEGIN
										SELECT	*
										FROM	@FolderExistence fe
										WHERE	fe.Exist NOT IN ('0', '1')
												AND fe.Exist IS NOT NULL

										SELECT	@ErrorMessage = 'Errors have occured when attempting to verify the following location: ' + @TypeOutputLocation + '.' + CHAR(13) + CHAR(10) +
																'Please review the provided information.'
										RAISERROR ( @ErrorMessage, 16, 1 )

									END

								IF EXISTS ( SELECT	*
											FROM	@FolderExistence fe
											WHERE	fe.Exist = 0 )
									BEGIN
										INSERT @SPFolder
											(
											Errors
											)
										EXEC (@SDFolderExec)

										IF EXISTS (	SELECT	*
													FROM	@SPFolder spf
													WHERE	spf.Errors IS NOT NULL )
											BEGIN
												SELECT	@ErrorMessage = 'Errors have occured when attempting to create the following location: ' + @TypeOutputLocation + '.' + CHAR(13) + CHAR(10) +
																		'Please review the provided information.'
												RAISERROR ( @ErrorMessage, 16, 1 )
											END
									END
							END
					END--@Run = 1

			END--@GenerateForRelease = 0

-- =============================================
-- Creation of Tables
-- =============================================
		CREATE TABLE #SprocInfo
			(
			ObjectID INT,
			ObjectName VARCHAR(500),
			ObjectType VARCHAR(10),
			SQLText VARCHAR(MAX),
			SQLTextCompact VARCHAR(MAX),
			SQLChecksum BIGINT
			)

-- =============================================
-- Initial Insert
-- =============================================
		INSERT #SprocInfo
			(
			ObjectID,
			ObjectName,
			ObjectType,
			SQLText
			)
		SELECT	o.object_id,
				o.name,
				o.type,
				REPLACE(REPLACE(REPLACE(sm.definition,CHAR(13)+CHAR(10),CHAR(10)),CHAR(13),CHAR(10)),CHAR(10),CHAR(13)+CHAR(10)) --Normalize all Lign Endings
		FROM	sys.objects o
				INNER JOIN sys.sql_modules sm ON sm.object_id = o.object_id
		WHERE	o.type IN (	SELECT	ot.Type COLLATE SQL_Latin1_General_CP1_CI_AS
							FROM	@ObjectTypes ot )
				AND o.name <> 'util_SprocDiff'
				AND o.name <> 'util_FindCustomizations'
				AND o.name <> 'util_Devops_ObjDiff'
				AND o.name <> 'util_Devops_FindCustomizations'
				AND o.name <> 'util_ObjOut'
		ORDER BY o.type,
				 o.name ASC

-- =============================================
-- Compact SQLText, removing comments and whitespace
-- =============================================
		DECLARE SQLCompactorCur CURSOR FORWARD_ONLY FOR
			SELECT	SQLText
			FROM	#SprocInfo
			FOR UPDATE OF SQLTextCompact
		OPEN SQLCompactorCur
		FETCH NEXT FROM SQLCompactorCur INTO @SQLTextCompact
		WHILE @@FETCH_STATUS = 0
			BEGIN
				SELECT	@Marker = 0
				SELECT	@NextLine = CHARINDEX('--',@SQLTextCompact)
				SELECT	@NextBlock = CHARINDEX('/*',@SQLTextCompact)

				WHILE ( @NextLine - @NextBlock <> 0 )
					BEGIN
						IF	( @NextLine < @NextBlock AND @NextLine <> 0 OR @NextBlock = 0 )
							BEGIN--line comment (--) is next
								SELECT	@Marker = @Marker + @NextLine
								SELECT	@StuffStart = @Marker
								SELECT	@StuffLength = ISNULL(NULLIF( CHARINDEX(CHAR(13)+CHAR(10),@SQLTextCompact,@StuffStart) ,0)-@StuffStart,LEN(@SQLTextCompact))
							END
						ELSE
							BEGIN--block comment (/**/) is next
								SELECT	@Marker = @Marker + @NextBlock
								SELECT	@NextBlockEnd = ISNULL(NULLIF( CHARINDEX('*/', REPLACE(@SQLTextCompact,'/*','//') ,@Marker) ,0)-@Marker+2,LEN(@SQLTextCompact))
								SELECT	@StuffLength = CHARINDEX('*/', REVERSE(SUBSTRING(@SQLTextCompact,@Marker,@NextBlockEnd)) ) + 1
								SELECT	@StuffStart = @Marker+@NextBlockEnd-@StuffLength
							END

						IF	( ( LEN(LEFT(@SQLTextCompact,@Marker)) - LEN(REPLACE(LEFT(@SQLTextCompact,@Marker),'''','')) ) % 2 <> 0 )
							BEGIN--comment is in a live string, increment forward
								SELECT	@Marker = CHARINDEX('''',@SQLTextCompact,@Marker)
								SELECT	@NextLine = ISNULL(NULLIF( CHARINDEX('--',@SQLTextCompact,@Marker) ,0)-@Marker,0)
								SELECT	@NextBlock = ISNULL(NULLIF( CHARINDEX('/*',@SQLTextCompact,@Marker) ,0)-@Marker,0)
							END
						ELSE
							BEGIN--comment is active, remove it
								SELECT	@SQLTextCompact = STUFF(@SQLTextCompact,@StuffStart,@StuffLength,' ')
								SELECT	@Marker = @Marker - 1
								SELECT	@NextLine = ISNULL(NULLIF( CHARINDEX('--',@SQLTextCompact,@Marker) ,0)-@Marker,0)
								SELECT	@NextBlock = ISNULL(NULLIF( CHARINDEX('/*',@SQLTextCompact,@Marker) ,0)-@Marker,0)
							END
					END
				--Strip all Empty Space
				UPDATE	si
				SET		si.SQLTextCompact = REPLACE(REPLACE(REPLACE(REPLACE(@SQLTextCompact,' ',''),CHAR(9),''),CHAR(10),''),CHAR(13),'')
				FROM	#SprocInfo si
				WHERE CURRENT OF SQLCompactorCur

				FETCH NEXT FROM SQLCompactorCur INTO @SQLTextCompact
			END
		CLOSE SQLCompactorCur
		DEALLOCATE SQLCompactorCur

-- =============================================
-- Generate Checksum
-- =============================================
		UPDATE	si
		SET		si.SQLChecksum = CONVERT(BIGINT,CONVERT(BINARY(4),CHECKSUM(si.SQLTextCompact)))
		FROM	#SprocInfo si

-- =============================================
-- Insert/Update AdminObjChecksum
-- =============================================
		IF (@GenerateForRelease = 1)
			BEGIN
				DELETE dbo.AdminObjChecksum

				INSERT dbo.AdminObjChecksum
					(
					ObjectName,
					ObjectType,
					ReleaseDBChecksum
					)
				SELECT	si.ObjectName,
						si.ObjectType,
						si.SQLChecksum
				FROM	#SprocInfo si
				ORDER BY si.ObjectType,
						 si.ObjectName

				IF (@SuppressOutput = 0)
					BEGIN
						PRINT 'IF (OBJECT_ID(''dbo.AdminObjChecksum'') IS NOT NULL)' + CHAR(13) + CHAR(10) +
							  CHAR(9) + 'BEGIN' + CHAR(13) + CHAR(10) +
							  CHAR(9) + CHAR(9) + 'TRUNCATE TABLE dbo.AdminObjChecksum' + CHAR(13) + CHAR(10) +
							  CHAR(9) + 'END' + CHAR(13) + CHAR(10) +
							  'ELSE' + CHAR(13) + CHAR(10) +
							  CHAR(9) + 'BEGIN' + CHAR(13) + CHAR(10) +
							  CHAR(9) + CHAR(9) + 'CREATE TABLE dbo.AdminObjChecksum' + CHAR(13) + CHAR(10) +
							  CHAR(9) + CHAR(9) + CHAR(9) + '(' + CHAR(13) + CHAR(10) +
							  CHAR(9) + CHAR(9) + CHAR(9) + 'AdminObjChecksumID INT IDENTITY (1,1),' + CHAR(13) + CHAR(10) +
							  CHAR(9) + CHAR(9) + CHAR(9) + 'ObjectName VARCHAR(500),' + CHAR(13) + CHAR(10) +
							  CHAR(9) + CHAR(9) + CHAR(9) + 'ObjectType VARCHAR(10),' + CHAR(13) + CHAR(10) +
							  CHAR(9) + CHAR(9) + CHAR(9) + 'ClientDBChecksum BIGINT,' + CHAR(13) + CHAR(10) +
							  CHAR(9) + CHAR(9) + CHAR(9) + 'ReleaseDBChecksum BIGINT' + CHAR(13) + CHAR(10) +
							  CHAR(9) + CHAR(9) + CHAR(9) + ')' + CHAR(13) + CHAR(10) +
							  CHAR(9) + CHAR(9) + 'CREATE NONCLUSTERED INDEX IX_AOC_AOCON' + CHAR(13) + CHAR(10) +
							  CHAR(9) + CHAR(9) + CHAR(9) + 'ON AdminObjChecksum' + CHAR(13) + CHAR(10) +
							  CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + '(ObjectName)' + CHAR(13) + CHAR(10) +
							   CHAR(9) + CHAR(9) + 'CREATE NONCLUSTERED INDEX IX_AOC_AOCOT' + CHAR(13) + CHAR(10) +
							  CHAR(9) + CHAR(9) + CHAR(9) + 'ON AdminObjChecksum' + CHAR(13) + CHAR(10) +
							  CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + '(ObjectType)' + CHAR(13) + CHAR(10) +
							  CHAR(9) + 'END' + CHAR(13) + CHAR(10) +
							  'GO' + CHAR(13) + CHAR(10) +
							  'BEGIN TRANSACTION' + CHAR(13) + CHAR(10) +
							  'INSERT INTO dbo.AdminObjChecksum' + CHAR(13) + CHAR(10) +
							  CHAR(9) + '(' + CHAR(13) + CHAR(10) +
							  CHAR(9) + 'ObjectName,' + CHAR(13) + CHAR(10) +
							  CHAR(9) + 'ObjectType,' + CHAR(13) + CHAR(10) +
							  CHAR(9) + 'ClientDBChecksum,' + CHAR(13) + CHAR(10) +
							  CHAR(9) + 'ReleaseDBChecksum' + CHAR(13) + CHAR(10) +
							  CHAR(9) + ')' + CHAR(13) + CHAR(10)

						DECLARE AOCInsertPrintCur CURSOR FAST_FORWARD FOR
							SELECT	'UNION ALL SELECT ''' + aoc.ObjectName + ''', ''' + aoc.ObjectType + ''', 0, ' + CONVERT(VARCHAR(MAX),aoc.ReleaseDBChecksum)
							FROM	AdminObjChecksum aoc
							ORDER BY aoc.ObjectType,
									 aoc.ObjectName ASC
						OPEN AOCInsertPrintCur
						FETCH NEXT FROM AOCInsertPrintCur INTO @InsertPrint
						SELECT	@InsertPrint = STUFF(@InsertPrint,1,10,'')
							WHILE @@FETCH_STATUS = 0
								BEGIN
									PRINT @InsertPrint

									FETCH NEXT FROM AOCInsertPrintCur INTO @InsertPrint
								END
						CLOSE AOCInsertPrintCur
						DEALLOCATE AOCInsertPrintCur

						PRINT 'COMMIT TRANSACTION'
					END--@SuppressOutput = 0
			END--@GenerateForRelease = 1
		ELSE--@GenerateForRelease = 0
			BEGIN
				UPDATE	aoc
				SET		aoc.ClientDBChecksum = si.SQLChecksum
				FROM	dbo.AdminObjChecksum aoc
						INNER JOIN #SprocInfo si ON si.ObjectName = aoc.ObjectName
													AND si.ObjectType = aoc.ObjectType

				DELETE	si
				FROM	#SprocInfo si
						LEFT JOIN dbo.AdminObjChecksum aoc ON aoc.ObjectName = si.ObjectName
															   AND aoc.ObjectType = si.ObjectType 
				WHERE	aoc.ClientDBChecksum = aoc.ReleaseDBChecksum
						OR aoc.ClientDBChecksum = 0
						OR aoc.AdminObjChecksumID IS NULL

				SELECT	@Row = 1
				WHILE @Count >= @Row
					BEGIN
						SELECT	@ObjType = ot.Type
						FROM	@ObjectTypes ot
						WHERE	ot.RowID = @Row

						SELECT	@Row = @Row + 1

						SELECT	@TypeOutputLocation = @OutputLocation + @ObjType + '\'

						IF (@SuppressOutput = 0)
							BEGIN
								DECLARE ObjOutCur CURSOR FAST_FORWARD FOR
									SELECT	'util_ObjOut ''' + si.ObjectName + ''', ''' + si.ObjectType + ''',''' + @TypeOutputLocation + '''' + ISNULL(',' + CONVERT(VARCHAR(1),@BCP) + '','')
									FROM	#SprocInfo si
									WHERE	si.ObjectType = @ObjType
								OPEN ObjOutCur
								FETCH NEXT FROM ObjOutCur INTO @SQLExec
									WHILE @@FETCH_STATUS = 0
										BEGIN
											EXEC (@SQLExec)

											FETCH NEXT FROM ObjOutCur INTO @SQLExec
										END
								CLOSE ObjOutCur
								DEALLOCATE ObjOutCur
							END--@SuppressOutput = 0
					END
			END--@GenerateForRelease = 0

-- =============================================
-- Error Catch
-- =============================================
	END TRY
	BEGIN CATCH
		IF (@@TRANCOUNT > 0)
			ROLLBACK

		PRINT 'ERRORS OCCURED NO CHANGES HAVE BEEN MADE'

		SELECT	@ErrorMessage = ERROR_MESSAGE()
		RAISERROR (@ErrorMessage,16,1)
	END CATCH

END
