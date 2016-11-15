/****** Object:  StoredProcedure [util_Dropper]    Script Date: 10/14/2016 11:17:16 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- =============================================
-- Author:		Chad Roesler
-- Create date: 06-08-2013
-- Rev date:	06-08-2013
-- Description:	<Description Here>
-- =============================================
/***********************************************
EXEC util_Dropper
***********************************************/
----------------------------
-- Modification: 
-- Modified By: Chad Roesler
-- Ticket Number: CR-000027
-- Modification Details: Initial Creation
-- Modification: This line needed for parsing reason
----------------------------
CREATE PROCEDURE [dbo].[util_Dropper]
AS
BEGIN
	SET NOCOUNT ON;
-- =============================================
-- Declaration of Variables
-- =============================================		
		DECLARE @FileName VARCHAR(MAX)
		DECLARE	@SQLExec VARCHAR(MAX)

		SELECT	@FileName = SUBSTRING(st.path, 0, LEN(st.path)-CHARINDEX('\',REVERSE(st.path)) + 1) + '\Log.trc'
		FROM	sys.traces st
		WHERE	st.is_default = 1

-- =============================================
-- Creation of Tables
-- =============================================
		CREATE TABLE #TablesToDrop
			(
			DropStatement VARCHAR(MAX)
			)
		
-- =============================================
-- Initial Insert of THE STUFF HERE
-- =============================================
		INSERT INTO #TablesToDrop
			(
			DropStatement
			)
		SELECT	'DROP TABLE ' + SUBSTRING(so.name,1,(CHARINDEX('_________________',so.name)-1)) AS DropStatement
		FROM	sys.fn_trace_gettable(@filename,default) as gt
				INNER JOIN tempdb.sys.objects as so ON gt.objectid = so.object_id
		WHERE	gt.DatabaseName = 'tempdb'
				AND so.type = 'u'
				AND gt.SPID = @@SPID
				AND so.name LIKE '%_________________%'
				AND so.name NOT LIKE '#TablesToDrop%'
				AND gt.LoginName = SUSER_NAME()

-- =============================================
-- Drop the Temp Tables Created
-- =============================================
		WHILE EXISTS (	SELECT	*
						FROM	#TablesToDrop )
			BEGIN
				SELECT	TOP(1)
						@SQLExec = ttd.DropStatement
				FROM	#TablesToDrop ttd
				
				EXEC (@SQLExec)
				
				DELETE	#TablesToDrop
				WHERE	DropStatement = @SQLExec
			END
			
		DROP TABLE #TablesToDrop
END