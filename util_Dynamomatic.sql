/****** Object:  StoredProcedure [dbo].[util_Dynamomatic]    Script Date: 3/14/2014 8:29:35 AM ******/
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
EXEC util_Dynamomatic
'SELECT	*,
		{@Var}
FROM	Table',
'@Var',
'{@Var}'
***********************************************/
/***********************************************
@SQLString:		SQL Text you want to parse
@VariableText:	Comma separated list of variables you want in the procedure
@ReplaceText:	Comma separated list of the text the variables should be replacing
NOTE:
@VariableText and @ReplaceText should have the same info passed
***********************************************/
----------------------------
-- Modification:
-- Modified By: Chad Roesler
-- Ticket Number: CR-000237
-- Modification Details: Initial Creation
-- Modification: This line needed for parsing reason
----------------------------
CREATE PROCEDURE [dbo].[util_Dynamomatic]
	(
	@SQLString VARCHAR(MAX),
	@VariableText VARCHAR(MAX) = NULL,
	@ReplaceText VARCHAR(MAX) = NULL
	)
AS
BEGIN
	SET NOCOUNT ON;
	BEGIN TRY
-- =============================================
-- Declaration of Variables
-- =============================================
		DECLARE	@RowID INT
		DECLARE	@Count INT
		DECLARE	@LineStart INT
		DECLARE	@LineEnd INT
		DECLARE	@LineData VARCHAR(MAX)
		DECLARE	@Variable VARCHAR(MAX)
		DECLARE	@Replace VARCHAR(MAX)
		DECLARE @ErrorMessage VARCHAR(MAX)
		DECLARE @ErrorSeverity INT
		DECLARE	@ErrorState INT

-- =============================================
-- Creation of Tables
-- =============================================
		CREATE TABLE #VariablesReplacement
			(
			RowID INT,
			Variable VARCHAR(MAX),
			ReplaceText VARCHAR(MAX)
			)

-- =============================================
-- Insert of the Variables and their ReplacementText
-- =============================================
		IF (@VariableText IS NOT NULL
			AND @ReplaceText IS NOT NULL)
			BEGIN
				INSERT INTO #VariablesReplacement
					(
					RowID,
					Variable,
					ReplaceText
					)
				SELECT	v.ID,
						''' + ' + v.SplitItem + ' + ''',
						r.SplitItem
				FROM	dbo.tvf_Split(@VariableText,',') v
						FULL JOIN dbo.tvf_Split(@ReplaceText,',') r ON r.ID = v.ID
			END

-- =============================================
-- Error Checking
-- =============================================
		IF EXISTS (	SELECT	vr.RowID
					FROM	#VariablesReplacement vr
					WHERE	vr.Variable IS NULL
							OR vr.ReplaceText IS NULL)
			BEGIN
				SELECT  @ErrorMessage = 'There is a different number of Variables and Replacetext'
				RAISERROR (@ErrorMessage, 16, 1)
			END
-- =============================================
-- Single Quote replacement and addition to the ends
-- =============================================
		SELECT	@SQLstring = REPLACE(@SQLSTRING,'''','''''')
		SELECT	@SQLString = '''' + @SQLString + ''''

-- =============================================
-- Replace CarriageReturns and LineFeeds
-- =============================================
		SELECT	@SQLString = REPLACE(REPLACE(REPLACE(@SQLString,CHAR(13) + CHAR(10),CHAR(10)),CHAR(13),CHAR(10)),CHAR(10),''' + CHAR(13) + CHAR(10) +' + CHAR(13) + CHAR(10) + '''')

-- =============================================
-- Replace the Replacement Text with the Variables
-- =============================================
		IF EXISTS (	SELECT	*
					FROM	#VariablesReplacement vr)
			BEGIN
				SELECT	@RowID = 1
				SELECT	@Count = COUNT(*)
				FROM	#VariablesReplacement
				WHILE @Count >= @RowID
					BEGIN
						SELECT	@Variable = vr.Variable
						FROM	#VariablesReplacement vr
						WHERE	vr.RowID = @RowID

						SELECT	@Replace = vr.ReplaceText
						FROM	#VariablesReplacement vr
						WHERE	vr.RowID = @RowID
				
						SELECT	@SQLString = REPLACE(@SQLString,@Replace,@Variable)
						SELECT	@RowID = @RowID + 1
					END
			END

-- =============================================
-- Repace Tabs, Tab begingings, return only lines
-- =============================================	
		SELECT	@SQLString = REPLACE(REPLACE(REPLACE(REPLACE(@SQLString,CHAR(9), ''' + CHAR(9) + '''),CHAR(13) + CHAR(10) + ''''' + CHAR(9) +',CHAR(13) + CHAR(10) + 'CHAR(9) +'),CHAR(13) + CHAR(10) + ''''' + CHAR(13) + CHAR(10)',CHAR(13) + CHAR(10) + 'CHAR(13) + CHAR(10)'),'+ '''' +','+')

-- =============================================
-- Remove the + '' at the end if it exists
-- =============================================	
		IF (SUBSTRING(@SQLString,LEN(@SQLString) - 4,LEN(@SQLString)) = ' + ''''')
			SELECT @SQLString = SUBSTRING(@SQLString,1,LEN(@SQLString) - 5)

		IF (SUBSTRING(@SQLString,LEN(@SQLString) - 5,LEN(@SQLString)) = ' +' + CHAR(13) + CHAR(10) + '''''')
			SELECT @SQLString = SUBSTRING(@SQLString,1,LEN(@SQLString) - 6)

-- =============================================
-- Print the Dynamic SQL
-- =============================================
		IF (@SQLString IS NOT NULL)
			BEGIN
				SELECT	@LineStart = 1

				SELECT	@LineEnd = 8001 - CHARINDEX(CHAR(10),REVERSE(SUBSTRING(@SQLString,@LineStart,8000)))

				SELECT	@LineData = SUBSTRING(@SQLString,@LineStart,@LineEnd)

				WHILE (@LineStart < LEN(@SQLString))
					BEGIN
						PRINT @LineData

						SELECT	@LineStart = @LineStart + @LineEnd

						SELECT	@LineEnd = 8001 - CHARINDEX(CHAR(10),REVERSE(SUBSTRING(@SQLString,@LineStart,8000)))

						SELECT	@LineData = SUBSTRING(@SQLString,@LineStart,@LineEnd)
					END
			END

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