/****** Object:  StoredProcedure [util_WHOUSESPRENAME_SERIOUSLY]    Script Date: 01/14/2016 11:34:10 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- =============================================
-- Author:		Chad Roesler
-- Create date: <Date>
-- Rev date:	<Date>
-- Description:	<Description Here>
-- =============================================
/***********************************************
EXEC [util_WHOUSESPRENAME_SERIOUSLY] @IgnoreDumbStuff = 'impexp_GetTargetTableData', @DoItForMe = 0
DROP PROCEDURE [util_WHOUSESPRENAME_SERIOUSLY] 
***********************************************/
----------------------------
-- Modification: 
-- Modified By: Chad Roesler
-- Ticket Number: N/A
-- Modification Details: Initial Creation
-- Modification: This line needed for parsing reason
----------------------------
CREATE PROCEDURE [dbo].[util_WHOUSESPRENAME_SERIOUSLY]
	(
	@IgnoreDumbstuff VARCHAR(MAX) = NULL,
	@DoItForMe BIT = 0
	)
AS
BEGIN
	SET NOCOUNT ON;
	BEGIN TRY
-- =============================================
-- Declaration of Variables
-- =============================================		
		DECLARE @ErrorMessage VARCHAR(MAX)
		DECLARE @ErrorSeverity INT
		DECLARE	@ErrorState INT
		DECLARE	@ProcText VARCHAR(MAX)
		DECLARE	@Count INT
		DECLARE	@RowID INT = 1
		DECLARE @LineStart INT
		DECLARE @LineEnd INT
		DECLARE @LineData VARCHAR(MAX)
-- =============================================
-- Creation of Tables
-- =============================================
		CREATE TABLE #WHYWOULDYOUDOTHIS
			(
			RowID INT IDENTITY (1,1),
			SPName VARCHAR(MAX),
			SPText VARCHAR(MAX),
			SPBadName VARCHAR(MAX),
			SPModText VARCHAR(MAX)
			)

		CREATE TABLE #IGNOREME
			(
			SPName VARCHAR(MAX)
			)
		
-- =============================================
-- Initial Insert of THE STUFF HERE
-- =============================================
		INSERT INTO #IGNOREME
			(
			SPName
			)
		SELECT	s.Item
		FROM	dbo.Split(@IgnoreDumbstuff,',') s

		INSERT INTO #WHYWOULDYOUDOTHIS
			(
			SPName,
			SPText,
			SPBadName,
			SPModText
			)
		SELECT	p.name,
				sm.definition,
				(	SELECT	s.Item
					FROM	dbo.Split(REPLACE(REPLACE(REPLACE(sm.definition,CHAR(13) + CHAR(10),CHAR(10)),CHAR(13),CHAR(10)),CHAR(10),CHAR(13) + CHAR(10)),CHAR(10) + CHAR(13)) s
					WHERE	s.Item LIKE 'CREATE PROC%'),
				REPLACE(sm.definition, (	SELECT	s.Item
											FROM	dbo.Split(REPLACE(REPLACE(REPLACE(sm.definition,CHAR(13) + CHAR(10),CHAR(10)),CHAR(13),CHAR(10)),CHAR(10),CHAR(13) + CHAR(10)),CHAR(10) + CHAR(13)) s
											WHERE	s.Item LIKE 'CREATE PROC%'),'ALTER PROCEDURE [dbo].[' + p.name + ']')
		FROM	sys.procedures p
				INNER JOIN sys.sql_modules sm ON sm.object_id = p.object_id
				LEFT JOIN #IGNOREME i ON i.SPName = p.name
		WHERE	sm.definition NOT LIKE '%' + p.name + '%'
				AND i.SPName IS NULL


		SELECT	@Count = COUNT(*)
		FROM	#WHYWOULDYOUDOTHIS w

-- =============================================
-- Template Header
-- =============================================
		WHILE	(@Count >= @RowID)
			BEGIN
				SELECT	@ProcText = w.SPModText
				FROM	#WHYWOULDYOUDOTHIS w
				WHERE	w.RowID = @RowID

				SELECT	@LineStart = 1

				SELECT	@LineEnd = 8001 - CHARINDEX(CHAR(10),REVERSE(SUBSTRING(@ProcText,@LineStart,8000)))

				SELECT	@LineData = SUBSTRING(@ProcText,@LineStart,@LineEnd)

				WHILE (@LineStart < LEN(@ProcText))
					BEGIN
						PRINT @LineData

						SELECT	@LineStart = @LineStart + @LineEnd

						SELECT	@LineEnd = 8001 - CHARINDEX(CHAR(10),REVERSE(SUBSTRING(@ProcText,@LineStart,8000)))

						SELECT	@LineData = SUBSTRING(@ProcText,@LineStart,@LineEnd)
					END

				IF (@DoItForMe = 1)
					BEGIN
						EXEC (@ProcText)
					END
				SELECT	@RowID = @RowID + 1
			END

	SELECT	*
	FROM	#WHYWOULDYOUDOTHIS
	END TRY
	
	BEGIN CATCH
	
		IF (@@TRANCOUNT > 0) 
			BEGIN
				ROLLBACK
				PRINT 'ERRORS OCCURED NO CHANGES HAVE BEEN MADE'
			END
			
		SELECT	@ErrorMessage = ERROR_MESSAGE(),
				@ErrorSeverity = ERROR_SEVERITY(),
				@ErrorState = ERROR_STATE()
		RAISERROR (@ErrorMessage,@ErrorSeverity,@ErrorState)
	END CATCH

END
