/************************************************************************************
-- Drop/Creation of util_ObjOut [2]
************************************************************************************/
-- =============================================
-- Author:		Chad Roesler
-- Create date: 06-16-2013
-- Rev date:	06-27-2013
-- Description:	Prints the Contents of a database
-- object.  Can also be used to export the object
-- to a specific folder.
-- Basis of creation was util_ScriptProc
-- =============================================
/***********************************************
EXEC util_ObjOut 'ProcedureNameHEre', 'p', 'C:\Users\Chad.Roesler\Desktop\New folder'
***********************************************/
----------------------------
-- Modification:
-- Modified By: Alec Hedlund
-- Ticket Number: CR-000038
-- Modification Details: Inclusion of Auto Typing
-- This is used for the server instance
-- Modification: This line needed for parsing reason
----------------------------
-- Modification:
-- Modified By: Chad Roesler
-- Ticket Number: CR-000038
-- Modification Details: Addition of Use of bcp
-- This is used for the server instance
-- Modification: This line needed for parsing reason
----------------------------
-- Modification:
-- Modified By: Chad Roesler
-- Ticket Number: CR-000038
-- Modification Details: Alteration of Variable @SIName
-- This is used for the server instance
-- Modification: This line needed for parsing reason
----------------------------
-- Modification:
-- Modified By: Chad Roesler
-- Ticket Number: CR-000038
-- Modification Details: Addition of Variable @SIName
-- This is used for the server instance
-- Modification: This line needed for parsing reason
----------------------------
-- Modification:
-- Modified By: Chad Roesler and Alec Hedlund
-- Ticket Number: CR-000038
-- Modification Details: Resolved issue of missing blocks of text
-- Resolved issues of additional CR+LF characters
-- Added final output to resolve double.sql issues
-- Modification: This line needed for parsing reason
----------------------------
-- Modification:
-- Modified By: Alec Hedlund
-- Ticket Number: CR-000038
-- Modification Details: Use of sys.sql_modules rather than syscomments
-- Updated Error Handling
-- Modification: This line needed for parsing reason
----------------------------
-- Modification:
-- Modified By: Chad Roesler
-- Ticket Number: CR-000038
-- Modification Details: Initial Creation
-- Modification: This line needed for parsing reason
----------------------------
CREATE PROCEDURE [dbo].[util_ObjOut]
	(
	@Name VARCHAR(MAX),
	@Type VARCHAR(10) = 'P',
	@OutputLocation VARCHAR(MAX) = NULL,
	@BCP BIT = 0
	)
AS
BEGIN
	SET NOCOUNT ON;
	BEGIN TRY
-- =============================================
-- Declaration of Variables
-- =============================================
		DECLARE	@ObjectID INT
		DECLARE	@ObjectDesc VARCHAR(MAX)
		DECLARE	@ObjectHeader VARCHAR(MAX)
		DECLARE	@LineStart INT
		DECLARE	@LineEnd INT
		DECLARE	@LineData VARCHAR(MAX)
		DECLARE	@AllLineData VARCHAR(MAX)
		DECLARE	@DBName VARCHAR(MAX)
		DECLARE	@SIName VARCHAR(MAX)
		DECLARE	@Run BIT
		DECLARE	@OuputCheck VARCHAR(MAX)
		DECLARE	@OutputCmd VARCHAR(MAX)
		DECLARE @FinalOutput VARCHAR(MAX)
		DECLARE @ErrorMessage VARCHAR(MAX)
		DECLARE @ErrorSeverity INT
		DECLARE	@ErrorState INT
		
		IF EXISTS (	SELECT	COUNT(*)
					FROM	sys.objects so
					WHERE	so.name = @Name
					HAVING	COUNT(*) = 1 )
			BEGIN
				SELECT	@Type = so.Type
				FROM	sys.objects so
				WHERE	so.name = @Name
			END

		SELECT	@Name = so.name
		FROM	sys.objects so
		WHERE	so.name = @Name
				AND so.type = @Type

		SELECT	@ObjectID = OBJECT_ID(@Name, @Type)

		SELECT	@ObjectDesc = CASE WHEN (@Type = 'V')
								   THEN 'View'
								   WHEN (@Type = 'TR')
								   THEN 'Trigger'
								   WHEN (@Type IN ('FN','FS','IF','TF'))
								   THEN 'UserDefinedFunction'
								   ELSE 'StoredProcedure'
								   END

		SELECT	@DBName = QUOTENAME(DB_NAME())

		SELECT	@SIName = ISNULL(NULLIF(CONVERT(VARCHAR(MAX),SERVERPROPERTY('ServerName')),''),@@SERVERNAME)

-- =============================================
-- Create ObjHeaderTable
-- =============================================
		IF OBJECT_ID('tempdb..##ObjHeader') IS NOT NULL
			DROP TABLE ##ObjHeader

		CREATE TABLE ##ObjHeader
			(
			ObjectHeader VARCHAR(MAX)
			)

-- =============================================
-- Error Checking
-- =============================================
		IF (@Type IN ('S', 'U', 'IT', 'D', 'F', 'PK', 'UQ', 'SQ'))
			BEGIN
				SELECT	@ErrorMessage = 'Improper Type of Object chosen, please ensure use of one of the following:' + (CHAR(13) + CHAR(10)) +
										CHAR(9) + 'FN: SQL_SCALAR_FUNCTION' + (CHAR(13) + CHAR(10)) +
										CHAR(9) + 'FS: CLR_SCALAR_FUNCTION' + (CHAR(13) + CHAR(10)) +
										CHAR(9) + 'IF: SQL_INLINE_TABLE_VALUED_FUNCTION' + (CHAR(13) + CHAR(10)) +
										CHAR(9) + 'P : SQL_STORED_PROCEDURE' + (CHAR(13) + CHAR(10)) +
										CHAR(9) + 'PC: CLR_STORED_PROCEDURE' + (CHAR(13) + CHAR(10)) +
										CHAR(9) + 'TF: SQL_TABLE_VALUED_FUNCTION' + (CHAR(13) + CHAR(10)) +
										CHAR(9) + 'TR: SQL_TRIGGER' + (CHAR(13) + CHAR(10)) +
										CHAR(9) + 'V : VIEW' + (CHAR(13) + CHAR(10))
				RAISERROR ( @ErrorMessage, 16, 1 )

			END

		IF ( @ObjectID IS NULL )
			BEGIN
				SELECT	@ErrorMessage = 'Object: ' + @Name + ' does not exist.' + (CHAR(13) + CHAR(10)) +
										'Please verify that an existing object name has been chosen and that the proper type is passed:' + (CHAR(13) + CHAR(10)) +
										CHAR(9) + 'FN: SQL_SCALAR_FUNCTION' + (CHAR(13) + CHAR(10)) +
										CHAR(9) + 'FS: CLR_SCALAR_FUNCTION' + (CHAR(13) + CHAR(10)) +
										CHAR(9) + 'IF: SQL_INLINE_TABLE_VALUED_FUNCTION' + (CHAR(13) + CHAR(10)) +
										CHAR(9) + 'P : SQL_STORED_PROCEDURE' + (CHAR(13) + CHAR(10)) +
										CHAR(9) + 'PC: CLR_STORED_PROCEDURE' + (CHAR(13) + CHAR(10)) +
										CHAR(9) + 'TF: SQL_TABLE_VALUED_FUNCTION' + (CHAR(13) + CHAR(10)) +
										CHAR(9) + 'TR: SQL_TRIGGER' + (CHAR(13) + CHAR(10)) +
										CHAR(9) + 'V : VIEW' + (CHAR(13) + CHAR(10))
				RAISERROR ( @ErrorMessage, 16, 1 )

			END

-- =============================================
-- Creation of Table for further Error checking
-- =============================================
		CREATE TABLE #cmdshellCheck
			(
			Name VARCHAR(MAX),
			Minimum BIT,
			Maximum BIT,
			Config_Value BIT,
			Run_Value BIT
			)

		CREATE TABLE #FolderExistence
			(
			Exist VARCHAR(MAX)
			)

		CREATE TABLE #OutputError
			(
			Message VARCHAR(MAX)
			)
			
-- =============================================
-- Insert for Table for further Error checking
-- =============================================
		INSERT INTO #cmdshellCheck
			(
			Name,
			Minimum,
			Maximum,
			Config_Value,
			Run_Value
			)
		EXEC master.dbo.sp_configure [xp_cmdshell]

		SELECT	@Run = cc.Run_Value
		FROM	#cmdshellCheck cc

		IF (@Run = 0 AND @OutputLocation IS NOT NULL)
			BEGIN
				SELECT	@ErrorMessage = 'xp_cmdshell is not configured on the server please enable xp_cmdshell.'
				RAISERROR ( @ErrorMessage, 16, 1 )

			END
		ELSE
			BEGIN
				SELECT	@OuputCheck = 'master.dbo.xp_cmdshell ''if exist "' + @OutputLocation + '" (echo 1) ELSE (echo 0)'''

				INSERT INTO #FolderExistence
					(
					Exist
					)
				EXEC (@OuputCheck)

				IF EXISTS (	SELECT	*
							FROM	#FolderExistence fe
							WHERE	fe.Exist NOT IN ('0', '1')
									AND fe.Exist IS NOT NULL )
					BEGIN
						SELECT	*
						FROM	#FolderExistence fe
						WHERE	fe.Exist NOT IN ('0', '1')
								AND fe.Exist IS NOT NULL

						SELECT	@ErrorMessage = 'Errors have occured when attempting to verify the following location: ' + @OutputLocation + '.' + CHAR(13) + CHAR(10) +
												'Please review the provided information.'
						RAISERROR ( @ErrorMessage, 16, 1 )

					END

				IF EXISTS ( SELECT	*
							FROM	#FolderExistence fe
							WHERE	fe.Exist = 0 )
					BEGIN
						SELECT	@ErrorMessage = 'Output Path: ' + @OutputLocation + ' does not exist.'
						RAISERROR ( @ErrorMessage, 16, 1 )

					END
			END

-- =============================================
-- Print Header Information
-- =============================================
		SELECT	@ObjectHeader = '/****** Object:  ' + @ObjectDesc + ' [' + @Name + ']    Script Date: ' + CONVERT(VARCHAR(25), GETDATE(), 101) + ' '	+ CONVERT(VARCHAR(25), GETDATE(), 108) + ' ******/' + CHAR(13) + CHAR(10) +
								'SET ANSI_NULLS ON' + CHAR(13) + CHAR(10) +
								'GO' + CHAR(13) + CHAR(10) +
								'SET QUOTED_IDENTIFIER ON' + CHAR(13) + CHAR(10) +
								'GO' + CHAR(13) + CHAR(10) +
								CHAR(13) + CHAR(10)
		IF (@BCP = 0)
		BEGIN
			PRINT @ObjectHeader
		END

		INSERT INTO ##ObjHeader
			(
			ObjectHeader
			)
		SELECT	@ObjectHeader
-- =============================================
-- Print Sproc Body
-- =============================================
		IF (@BCP = 0)
			BEGIN
				SELECT	@AllLineData = REPLACE(REPLACE(REPLACE(sm.definition,CHAR(13) + CHAR(10),CHAR(10)),CHAR(13),CHAR(10)),CHAR(10),CHAR(13) + CHAR(10))
				FROM	sys.sql_modules sm
				WHERE	sm.object_id = @ObjectID

				SELECT	@LineStart = 1

				SELECT	@LineEnd = 8001 - CHARINDEX(CHAR(10),REVERSE(SUBSTRING(@AllLineData,@LineStart,8000)))

				SELECT	@LineData = SUBSTRING(@AllLineData,@LineStart,@LineEnd)

				WHILE (@LineStart < LEN(@AllLineData))
					BEGIN
						PRINT @LineData

						SELECT	@LineStart = @LineStart + @LineEnd

						SELECT	@LineEnd = 8001 - CHARINDEX(CHAR(10),REVERSE(SUBSTRING(@AllLineData,@LineStart,8000)))

						SELECT	@LineData = SUBSTRING(@AllLineData,@LineStart,@LineEnd)
					END
			END

-- =============================================
-- Output portion
-- =============================================
	IF (@OutputLocation IS NOT NULL)
		BEGIN
			IF (SUBSTRING(REVERSE(@OutputLocation),1,1) <> '\')
				BEGIN
					SELECT	@FinalOutput = @OutputLocation + '\' + @Name + '.sql'
				END
			ELSE
				BEGIN
					SELECT	@FinalOutput = @OutputLocation + @Name + '.sql'
				END

			IF (@BCP = 1)
				BEGIN
					SELECT	@OutputCmd = 'master.dbo.xp_cmdshell ''bcp "SELECT oh.ObjectHeader + sm.definition FROM ' + @DBName + '.sys.sql_modules sm  CROSS APPLY ##ObjHeader oh WHERE sm.object_id = ' + CONVERT(VARCHAR(MAX),@ObjectID) + '" queryout "' + @FinalOutput + '" -S ' + @SIName + ' -T  -c -UTF8'''
				END
			ELSE
				BEGIN
					SELECT	@OutputCmd = 'master.dbo.xp_cmdshell ''sqlcmd -S ' + @SIName + ' -d "' + @DBName + '" -q "EXEC dbo.util_ObjOut ''''' + @Name + ''''', '''''+ @Type +''''', ''''' + @OutputLocation + '''''" -o "' + @FinalOutput + '" -y 8000'''
				END
			

			INSERT INTO #OutputError
				(
				Message
				)
			EXEC (@OutputCmd)

			IF EXISTS (	SELECT	*
						FROM	#OutputError oe
						WHERE	oe.Message IS NOT NULL 
								AND oe.Message NOT IN ('Starting copy...','1 rows copied.') 
								AND oe.Message NOT LIKE 'Network packet size (bytes):%'
								AND oe.Message NOT LIKE 'Clock Time (ms.) Total     : %')
				BEGIN

						SELECT	*
						FROM	#OutputError oe
						WHERE	oe.Message IS NOT NULL

						SELECT	@ErrorMessage = 'Errors have occured when attempting output the file.' + CHAR(13) + CHAR(10) +
												'Please review the provided information.'
						RAISERROR ( @ErrorMessage, 16, 1 )

				END

		END
	END TRY
	BEGIN CATCH

		IF (@@TRANCOUNT > 0)
			ROLLBACK
			PRINT 'ERRORS OCCURED NO CHANGES HAVE BEEN MADE'

		SELECT	@ErrorMessage = ERROR_MESSAGE(),
				@ErrorSeverity = ERROR_SEVERITY(),
				@ErrorState = ERROR_STATE()
		RAISERROR (@ErrorMessage,@ErrorSeverity,@ErrorState)

	END CATCH

END