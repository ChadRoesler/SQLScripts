/****** Object:  StoredProcedure [dbo].[util_BackupTableDiff]    Script Date: 3/25/2014 8:38:12 AM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO


-- =============================================
-- Author:		Chad Roesler
-- Create date: 06-24-2012
-- Rev:			05-18-2013
-- Description:	Personal Use Only.
-- Compares a Backup table to the Root Table and
-- displays any differences between the two.
-- Allows for the creation of Update, Insert
-- and Delete Statements.
--
-- Please Note: XML Comparison does occur in
-- this script, it also takes a substancial
-- amount of time to complete, (roughly 1 sec per row)
-- You can set XML to 0 to not compare XML.
-- Setting this as 0 will also leave it out of
-- the update statement written.
-- =============================================
/***********************************************
UTIL_BackupTableDiff	@TableOne = X
					   ,@TableTwo = X
					   ,@SkipRootTableCheck = 0
					   ,@XML = 0
					   ,@PartialTable = 0
					   ,@Insert = 0
					   ,@Update = 0
					   ,@Delete = 0
					   ,@Debug = 1

Instructions:
@TableOne:				The Backup Table
@TableTwo:				Leave NULL is you want to compare against the root table
						You can declare another Table here if you want to compare two backup tables
@SkipRootTableCheck:	Set this to 1 if you the naming conventions are different than my Standard yet have the same RootTable
@XML:					This will do XML comparison, please read the warning above about XML comparison
@PartialTable:			Set to 1 if @TableOne is a partial table (Usually specially labeled)
						If set to 0 it will check to see if its a partial table and will suggest setting it to 1
@Insert					Set to 1 to output the print statment to insert previously deleted rows
						This will also query against any fk constraints to see if they may need to have constrained information inserted
@Update					Set to 1 to output the print statement to update previous changed info
@Delete					Set to 1 to output the print statement to delete inserted rows
@Debug					Set to 1 See all of the printed SQL Execs
						If set to 0 it will return the results of the diff table.

***********************************************/
----------------------------
-- Modification:
-- Modified By: Chad Roesler
-- Ticket Number: CR-000001
-- Modification Details: Initial Creation
-- Modification: This line needed for parsing reason
----------------------------
ALTER PROCEDURE [dbo].[util_BackupTableDiff]
	(
	@TableOne VARCHAR(MAX),			--Inital Table Put in
	@TableTwo VARCHAR(MAX) = NULL,	--Second Table Hidden Feature
	@SkipRootTableCheck INT = 1,	--Skip Root Table comparison
	@XML BIT = 0,					--Compare XML
	@PartialTable BIT = 0,			--Partial Table Backup
	@Insert BIT = 0,				--Insert Into Global Temp
	@Update BIT = 0,				--Creates Update based on Changed Info
	@Delete BIT = 0,				--Deletion of New Rows to the Table
	@Debug BIT = 0					--Debug Flag Runs Prints no select is run.
	)
AS
BEGIN
	BEGIN TRY
-- =====================
-- Variables Assemble!
-- =====================
		DECLARE @PriKey VARCHAR(MAX)	--PrimaryKey of the Tables
		DECLARE	@JoinType VARCHAR(MAX)	--Join Type for Partial Tables
		DECLARE	@SQLRowCnt VARCHAR(MAX)	--Original Table Row Count
		DECLARE	@PossiblePT BIT	= 0		--Possible Partial Table
		DECLARE @SQLUpColL VARCHAR(MAX)	--Column List Gathering
		DECLARE @SQLUpTable VARCHAR(MAX)--UPDATE CREATE TABLE Declaration
		DECLARE @SQLUpdate VARCHAR(MAX) --UPDATE Declaration
		DECLARE @SQLUpOut VARCHAR(MAX)	--UPDATE OUTPUT Declaration
		DECLARE @SQLUpFrom VARCHAR(MAX)	--UPDATE FROM Declaration
		DECLARE @SQLUpWhere VARCHAR(MAX)--UPDATE WHERE Declaration
		DECLARE @SQLDeTable VARCHAR(MAX)--DELETE CREATE TABLE Declaration
		DECLARE @SQLDelete VARCHAR(MAX) --DELETE Declaration
		DECLARE @SQLDeOut VARCHAR(MAX)	--DELETE OUTPUT Declaration
		DECLARE @SQLDeFrom VARCHAR(MAX) --DELETE FROM Declaration
		DECLARE @SQLDeWhere VARCHAR(MAX)--DELETE WHERE Declaration
		DECLARE @SQLInTable VARCHAR(MAX)--INSERT CREATE TABLE Declaration
		DECLARE	@SQLInsert VARCHAR(MAX) --INSERT Declaration
		DECLARE @SQLInOut VARCHAR(MAX)	--INSERT OUTPUT Declaration
		DECLARE @SQLInSel VARCHAR(MAX)	--INSERT SELECT Declaration
		DECLARE @SQLInFrom VARCHAR(MAX) --INSERT FROM Declaration
		DECLARE @SQLInWhere VARCHAR(MAX)--INSERT WHERE Declaration
		DECLARE @SQLSelect VARCHAR(MAX)	--SELECT Statement
		DECLARE @SQLGloIn VARCHAR(MAX)	--Global INSERT Setup
		DECLARE @SQLFrom VARCHAR(MAX)	--FROM Declaration
		DECLARE @SQLWhere1 VARCHAR(MAX)	--First Part WHERE Clause
		DECLARE @SQLWhere2 VARCHAR(MAX)	--Second Part WHERE Clause
		DECLARE @SQLWhere3 VARCHAR(MAX)	--Third Part WHERE Clause
		DECLARE @SQLGlobal VARCHAR(MAX)	--Global Temp Selection
		DECLARE @SQLDrop VARCHAR(MAX)	--DROP Declaration
		DECLARE @SQLBackUp VARCHAR(MAX) --BackupTable Declaration
		DECLARE @Count INT				--Count of Rows
		DECLARE	@UpCount INT			--Count of Rows for Update
		DECLARE @UpCol VARCHAR(MAX)		--Gather Column Name
		DECLARE @Row INT				--Row Choice
		DECLARE @CompareOne VARCHAR(MAX)--Source for Comparison
		DECLARE @CompareTwo VARCHAR(MAX)--Source for Comparison
		DECLARE @DiffTable VARCHAR(MAX)	--New Diff Table Name
		DECLARE @RootTable VARCHAR(MAX)	--Find Root Table
		DECLARE @DBName VARCHAR(MAX)	--Get Current DB Name
		DECLARE	@SQLFNExec VARCHAR(MAX)	--EXEC statement for creating Missing udf (SQL 2005 compliant)
		DECLARE @SQLGTPK NVARCHAR(MAX)	--dbo.udf_GetTablePK
		DECLARE @SQLCBP NVARCHAR(MAX)	--dbo.udf_ColumnByPosition
		DECLARE @SQLCT NVARCHAR(MAX)	--dbo.udf_ColumnType
		DECLARE @SQLCXML NVARCHAR(MAX)	--dbo.CompareXML
		DECLARE	@SQLSplit NVARCHAR(MAX)	--dbo.tvf_Split
		DECLARE @ErrorMessage VARCHAR(MAX) --Error Message
		DECLARE @ErrorSeverity INT		   --Error Severity
		DECLARE	@ErrorState INT			   --Error State

-- ======================
-- Gather DB Name
-- Generate EXEC
-- ======================
		SELECT	@DBName = DB_NAME()
		SELECT	@SQLFNExec = @DBName + '.dbo.sp_executesql'

-- ======================
-- Create Split2
-- ======================
		IF (OBJECT_ID('dbo.tvf_Split','TF') IS NULL)
			BEGIN
				SELECT	@SQLSplit = '-- =============================================' + (CHAR(13) + CHAR(10)) +
									'-- Author:' + CHAR(9) + CHAR(9) + 'Chad Roesler' + (CHAR(13) + CHAR(10)) +
									'-- Create date: 03-18-2013' + (CHAR(13) + CHAR(10)) +
									'-- Rev date:' + CHAR(9) + 'N/A' + (CHAR(13) + CHAR(10)) +
									'-- Description:' + CHAR(9) + 'Splits a string of data into a ' + (CHAR(13) + CHAR(10)) +
									'-- muliti row table' + (CHAR(13) + CHAR(10)) +
									'-- =============================================' + (CHAR(13) + CHAR(10)) +
									'----------------------------' + (CHAR(13) + CHAR(10)) +
									'-- Modification: ' + (CHAR(13) + CHAR(10)) +
									'-- Modified By: Chad Roesler' + (CHAR(13) + CHAR(10)) +
									'-- Ticket Number: CR-000002' + (CHAR(13) + CHAR(10)) +
									'-- Modification Details: Initial Creation' + (CHAR(13) + CHAR(10)) +
									'-- Modification: This line needed for parsing reason' + (CHAR(13) + CHAR(10)) +
									'----------------------------' + (CHAR(13) + CHAR(10)) +
									'CREATE FUNCTION [dbo].[tvf_Split]' + (CHAR(13) + CHAR(10)) +
									CHAR(9) + '(' + (CHAR(13) + CHAR(10)) +
									CHAR(9) + '@DataSet VARCHAR(MAX),' + (CHAR(13) + CHAR(10)) +
									CHAR(9) + '@Delimiter VARCHAR(MAX)' + (CHAR(13) + CHAR(10)) +
									CHAR(9) + ')' + (CHAR(13) + CHAR(10)) +
									'RETURNS' + CHAR(9) + '@SplitTable TABLE' + (CHAR(13) + CHAR(10)) +
									CHAR(9) + CHAR(9) + '(' + (CHAR(13) + CHAR(10)) +
									CHAR(9) + CHAR(9) + 'ID INT NOT NULL IDENTITY,' + (CHAR(13) + CHAR(10)) +
									CHAR(9) + CHAR(9) + 'SplitItem VARCHAR(MAX)' + (CHAR(13) + CHAR(10)) +
									CHAR(9) + CHAR(9) + ')' + (CHAR(13) + CHAR(10)) +
									'AS' + (CHAR(13) + CHAR(10)) +
									'BEGIN' + (CHAR(13) + CHAR(10)) +
									'-- =============================================' + (CHAR(13) + CHAR(10)) +
									'-- Initial Insert of the Dataset Split by the ' + (CHAR(13) + CHAR(10)) +
									'-- Delimiter into the Table' + (CHAR(13) + CHAR(10)) +
									'-- =============================================' + (CHAR(13) + CHAR(10)) +
									CHAR(9) + 'WHILE (CHARINDEX(@Delimiter,@DataSet) > 0)' + (CHAR(13) + CHAR(10)) +
									CHAR(9) + CHAR(9) + 'BEGIN' + (CHAR(13) + CHAR(10)) +
									CHAR(9) + CHAR(9) + CHAR(9) + 'INSERT INTO @SplitTable' + (CHAR(13) + CHAR(10)) +
									CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + '(' + (CHAR(13) + CHAR(10)) +
									CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + 'SplitItem' + (CHAR(13) + CHAR(10)) +
									CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + ')' + (CHAR(13) + CHAR(10)) +
									CHAR(9) + CHAR(9) + CHAR(9) + 'SELECT' + CHAR(9) + 'LTRIM(RTRIM(SUBSTRING(@DataSet,1,(CHARINDEX(@Delimiter,@DataSet) - 1))))' + (CHAR(13) + CHAR(10)) +
									(CHAR(13) + CHAR(10)) +
									CHAR(9) + CHAR(9) + CHAR(9) + 'SELECT' + CHAR(9) + '@DataSet = SUBSTRING(@DataSet,(CHARINDEX(@Delimiter,@DataSet) + 1),LEN(@DataSet))' + (CHAR(13) + CHAR(10)) +
									CHAR(9) + CHAR(9) + 'END' + (CHAR(13) + CHAR(10)) +
									(CHAR(13) + CHAR(10)) +
									'-- =============================================' + (CHAR(13) + CHAR(10)) +
									'-- Final Insert to catch last of data' + (CHAR(13) + CHAR(10)) +
									'-- =============================================' + (CHAR(13) + CHAR(10)) +
									CHAR(9) + 'INSERT INTO @SplitTable' + (CHAR(13) + CHAR(10)) +
									CHAR(9) + CHAR(9) + '(' + (CHAR(13) + CHAR(10)) +
									CHAR(9) + CHAR(9) + 'SplitItem' + (CHAR(13) + CHAR(10)) +
									CHAR(9) + CHAR(9) + ')' + (CHAR(13) + CHAR(10)) +
									CHAR(9) + 'SELECT' + CHAR(9) + 'LTRIM(RTRIM(@DataSet))' + (CHAR(13) + CHAR(10)) +
									(CHAR(13) + CHAR(10)) +
									CHAR(9) + 'RETURN' + (CHAR(13) + CHAR(10)) +
									(CHAR(13) + CHAR(10)) +
									'END'

				SELECT	@SQLSplit = N'' + @SQLSplit

				EXEC @SQLFNExec @SQLSplit
			END

-- ======================
-- Gather Root Table
-- NOTE: Here is where you can modify the root table extration
-- based on your backup table nomenclature
-- Settup a check for skipping root table check
-- Adding additional setup for checking if its an upgrade backup
-- ======================
		IF OBJECT_ID(@DBName + '..' + @TableOne) IS NULL
			BEGIN
				SELECT	@ErrorMessage = @TableOne + ' does not exist.'
				RAISERROR (@ErrorMessage, 16, 1)
			END
		IF 	(@SkipRootTableCheck = 0)
			BEGIN
				IF (@TableTwo IS NOT NULL)
					BEGIN
						IF (@TableOne LIKE 'v[0-9][0-9][0-9][0-9][0-9]!_%!_[0-9][0-9][0-9][0-9][0-9][0-9]%' ESCAPE '!')
							BEGIN
								SELECT	@CompareOne = t1.SplitItem
								FROM	dbo.tvf_Split(@TableOne,'_') t1
								WHERE	t1.ID = 2
							END
						ELSE
							BEGIN
								SELECT	@CompareOne = SUBSTRING(REPLACE(t1.SplitItem,d.CDate,''),CASE WHEN t1.SplitItem LIKE 'zz%'
																									  THEN 3
																									  ELSE 1 
																									  END,LEN(REPLACE(t1.SplitItem,d.CDate,'')))
								FROM	dbo.tvf_Split(@TableOne,'_') t1
										CROSS JOIN (SELECT	REPLACE(CONVERT(VARCHAR(MAX),CONVERT(DATE,t.create_date), 110),'-','') AS CDate
													FROM	sys.tables t
													WHERE	t.name = @TableOne ) AS d
								WHERE	t1.ID = 1
							END

						IF (@TableTwo LIKE 'v[0-9][0-9][0-9][0-9][0-9]!_%!_[0-9][0-9][0-9][0-9][0-9][0-9]%' ESCAPE '!')
							BEGIN
								SELECT	@CompareTwo = t1.SplitItem
								FROM	dbo.tvf_Split(@TableTwo,'_') t1
								WHERE	t1.ID = 2
							END
						ELSE
							BEGIN
								SELECT	@CompareTwo = SUBSTRING(REPLACE(t1.SplitItem,d.CDate,''),CASE WHEN t1.SplitItem LIKE 'zz%'
																									  THEN 3
																									  ELSE 1 
																									  END,LEN(REPLACE(t1.SplitItem,d.CDate,'')))
								FROM	dbo.tvf_Split(@TableTwo,'_') t1
										CROSS JOIN (SELECT	REPLACE(CONVERT(VARCHAR(MAX),CONVERT(DATE,t.create_date), 110),'-','') AS CDate
													FROM	sys.tables t
													WHERE	t.name = @TableTwo ) AS d
								WHERE	t1.ID = 1
							END

						IF (@CompareOne <> @CompareTwo)
							BEGIN
								SELECT	@ErrorMessage = 'The two tables do not have the same Root Table ' + @TableOne + ' came from ' + @CompareOne + ', ' + @TableTwo + ' came from ' + @CompareTwo + '.'
								RAISERROR (@ErrorMessage, 16, 1)
							END
						ELSE
							BEGIN
								SELECT	@RootTable = @CompareTwo
							END
					END
				ELSE
					BEGIN
						IF (@TableOne LIKE 'v[0-9][0-9][0-9][0-9][0-9]!_%!_[0-9][0-9][0-9][0-9][0-9][0-9]%' ESCAPE '!')
							BEGIN
								SELECT	@TableTwo = t1.SplitItem
								FROM	dbo.tvf_Split(@TableOne,'_') t1
								WHERE	t1.ID = 2
							END
						ELSE
							BEGIN
								SELECT	@TableTwo = SUBSTRING(REPLACE(t1.SplitItem,d.CDate,''),CASE WHEN t1.SplitItem LIKE 'zz%'
																									THEN 3
																									ELSE 1 
																									END,LEN(REPLACE(t1.SplitItem,d.CDate,'')))
								FROM	dbo.tvf_Split(@TableTwo,'_') t1
										CROSS JOIN (SELECT	REPLACE(CONVERT(VARCHAR(MAX),CONVERT(DATE,t.create_date), 110),'-','') AS CDate
													FROM	sys.tables t
													WHERE	t.name = @TableTwo ) AS d
								WHERE	t1.ID = 1
							END

						SELECT	@RootTable = @TableTwo
					END
			END
		ELSE
			BEGIN
				SELECT @RootTable = @TableTwo
			END

-- ======================
-- Create CompareXML
-- ======================
		IF (OBJECT_ID('dbo.CompareXML','FN') IS NULL)
			BEGIN
				SELECT	@SQLCXML =	'-- =============================================' + (CHAR(13) + CHAR(10)) +
									'-- Author:		Jacob Sebastian' + (CHAR(13) + CHAR(10)) +
									'-- Create date: 09-14-2008' + (CHAR(13) + CHAR(10)) +
									'-- Rev date:	09-14-2008' + (CHAR(13) + CHAR(10)) +
									'-- Description:	Comparison of Two XML values' + (CHAR(13) + CHAR(10)) +
									'-- http://beyondrelational.com/modules/2/blogs/28/posts/10317/xquery-lab-36-writing-a-tsql-function-to-compare-two-xml-values-part-2.aspx' + (CHAR(13) + CHAR(10)) +
									'-- =============================================' + (CHAR(13) + CHAR(10)) +
									'----------------------------' + (CHAR(13) + CHAR(10)) +
									'-- Modification:' + (CHAR(13) + CHAR(10)) +
									'-- Modified By: Chad Roesler' + (CHAR(13) + CHAR(10)) +
									'-- Ticket Number: CR-000003' + (CHAR(13) + CHAR(10)) +
									'-- Modification Details: Initial Creation' + (CHAR(13) + CHAR(10)) +
									'-- Modification: This line needed for parsing reason' + (CHAR(13) + CHAR(10)) +
									'----------------------------' + (CHAR(13) + CHAR(10)) +
									'CREATE FUNCTION [dbo].[CompareXml]' + (CHAR(13) + CHAR(10)) +
									CHAR(9) + '(' + (CHAR(13) + CHAR(10)) +
									CHAR(9) + '@xml1 XML,' + (CHAR(13) + CHAR(10)) +
									CHAR(9) + '@xml2 XML' + (CHAR(13) + CHAR(10)) +
									CHAR(9) + ')' + (CHAR(13) + CHAR(10)) +
									'RETURNS INT' + (CHAR(13) + CHAR(10)) +
									'AS' + (CHAR(13) + CHAR(10)) +
									'BEGIN' + (CHAR(13) + CHAR(10)) +
									CHAR(9) + 'DECLARE @ret INT' + (CHAR(13) + CHAR(10)) +
									CHAR(9) + 'SELECT' + CHAR(9) + '@ret = 0' + (CHAR(13) + CHAR(10)) +
									'-- -------------------------------------------------------------' + (CHAR(13) + CHAR(10)) +
									'-- If one of the arguments is NULl then we assume that they are' + (CHAR(13) + CHAR(10)) +
									'-- not equal.' + (CHAR(13) + CHAR(10)) +
									'-- -------------------------------------------------------------' + (CHAR(13) + CHAR(10)) +
									CHAR(9) + 'IF (@xml1 IS NULL OR @xml2 IS NULL)' + (CHAR(13) + CHAR(10)) +
									CHAR(9) + CHAR(9) + 'BEGIN' + (CHAR(13) + CHAR(10)) +
									CHAR(9) + CHAR(9) + CHAR(9) + 'RETURN 1' + (CHAR(13) + CHAR(10)) +
									CHAR(9) + CHAR(9) + 'END' + (CHAR(13) + CHAR(10)) +
									'-- -------------------------------------------------------------' + (CHAR(13) + CHAR(10)) +
									'-- Match the name of the elements' + (CHAR(13) + CHAR(10)) +
									'-- -------------------------------------------------------------' + (CHAR(13) + CHAR(10)) +
									CHAR(9) + 'IF (SELECT' + CHAR(9) + '@xml1.value(''(local-name((/*)[1]))'',''VARCHAR(MAX)'')) <> (SELECT @xml2.value(''(local-name((/*)[1]))'',''VARCHAR(MAX)''))' + (CHAR(13) + CHAR(10)) +
									CHAR(9) + CHAR(9) + 'BEGIN' + (CHAR(13) + CHAR(10)) +
									CHAR(9) + CHAR(9) + CHAR(9) + 'RETURN 1' + (CHAR(13) + CHAR(10)) +
									CHAR(9) + CHAR(9) + 'END' + (CHAR(13) + CHAR(10)) +
									'-- -------------------------------------------------------------' + (CHAR(13) + CHAR(10)) +
									'-- Match the value of the elements' + (CHAR(13) + CHAR(10)) +
									'-- -------------------------------------------------------------' + (CHAR(13) + CHAR(10)) +
									CHAR(9) + 'DECLARE @elValue1 VARCHAR(MAX)' + (CHAR(13) + CHAR(10)) +
									CHAR(9) + 'DECLARE @elValue2 VARCHAR(MAX)' + (CHAR(13) + CHAR(10)) +
									CHAR(9) + 'SELECT' + CHAR(9) + '@elValue1 = @xml1.value(''((/*)[1])'',''VARCHAR(MAX)'')' + (CHAR(13) + CHAR(10)) +
									CHAR(9) + 'SELECT' + CHAR(9) + '@elValue2 = @xml2.value(''data((/*)[1])'',''VARCHAR(MAX)'')' + (CHAR(13) + CHAR(10)) +
									CHAR(9) + 'IF  @elValue1 <> @elValue2' + (CHAR(13) + CHAR(10)) +
									CHAR(9) + CHAR(9) + 'BEGIN' + (CHAR(13) + CHAR(10)) +
									CHAR(9) + CHAR(9) + CHAR(9) + 'RETURN 1' + (CHAR(13) + CHAR(10)) +
									CHAR(9) + CHAR(9) + 'END' + (CHAR(13) + CHAR(10)) +
									'-- -------------------------------------------------------------' + (CHAR(13) + CHAR(10)) +
									'-- Match the number of attributes' + (CHAR(13) + CHAR(10)) +
									'-- -------------------------------------------------------------' + (CHAR(13) + CHAR(10)) +
									CHAR(9) + 'DECLARE @attCnt1 INT' + (CHAR(13) + CHAR(10)) +
									CHAR(9) + 'DECLARE @attCnt2 INT' + (CHAR(13) + CHAR(10)) +
									CHAR(9) + 'SELECT' + CHAR(9) + '@attCnt1 = @xml1.query(''count(/*/@*)'').value(''.'',''INT'')' + (CHAR(13) + CHAR(10)) +
									CHAR(9) + 'SELECT' + CHAR(9) + '@attCnt2 = @xml2.query(''count(/*/@*)'').value(''.'',''INT'')' + (CHAR(13) + CHAR(10)) +
									CHAR(9) + 'IF @attCnt1 <> @attCnt2' + (CHAR(13) + CHAR(10)) +
									CHAR(9) + CHAR(9) + 'BEGIN' + (CHAR(13) + CHAR(10)) +
									CHAR(9) + CHAR(9) + CHAR(9) + 'RETURN 1' + (CHAR(13) + CHAR(10)) +
									CHAR(9) + CHAR(9) + 'END' + (CHAR(13) + CHAR(10)) +
									'-- -------------------------------------------------------------' + (CHAR(13) + CHAR(10)) +
									'-- Match the attributes of attributes' + (CHAR(13) + CHAR(10)) +
									'-- Here we need to run a loop over each attribute in the' + (CHAR(13) + CHAR(10)) +
									'-- to see if it exists and is the same' + (CHAR(13) + CHAR(10)) +
									'-- -------------------------------------------------------------' + (CHAR(13) + CHAR(10)) +
									CHAR(9) + 'DECLARE @cnt INT' + (CHAR(13) + CHAR(10)) +
									CHAR(9) + 'DECLARE @attName VARCHAR(MAX)' + (CHAR(13) + CHAR(10)) +
									CHAR(9) + 'DECLARE @attValue VARCHAR(MAX)' + (CHAR(13) + CHAR(10)) +
									CHAR(9) + 'SELECT' + CHAR(9) + '@cnt = 1' + (CHAR(13) + CHAR(10)) +
									CHAR(9) + 'WHILE (@cnt <= @attCnt1)' + (CHAR(13) + CHAR(10)) +
									CHAR(9) + CHAR(9) + 'BEGIN' + (CHAR(13) + CHAR(10)) +
									CHAR(9) + CHAR(9) + CHAR(9) + 'SELECT' + CHAR(9) + '@attName = NULL' + (CHAR(13) + CHAR(10)) +
									CHAR(9) + CHAR(9) + CHAR(9) + 'SELECT' + CHAR(9) + '@attValue = NULL' + (CHAR(13) + CHAR(10)) +
									CHAR(9) + CHAR(9) + CHAR(9) + 'SELECT' + CHAR(9) + '@attName = @xml1.value(''local-name((/*/@*[sql:variable("@cnt")])[1])'',''varchar(MAX)'')' + (CHAR(13) + CHAR(10)) +
									CHAR(9) + CHAR(9) + CHAR(9) + 'SELECT' + CHAR(9) + '@attValue = @xml1.value(''(/*/@*[sql:variable("@cnt")])[1]'',''varchar(MAX)'')' + (CHAR(13) + CHAR(10)) +
									'-- check if the attribute exists in the other XML document' + (CHAR(13) + CHAR(10)) +
									CHAR(9) + CHAR(9) + CHAR(9) + 'IF (@xml2.exist(''(/*/@*[local-name()=sql:variable("@attName")])[1]'') = 0)' + (CHAR(13) + CHAR(10)) +
									CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + 'BEGIN' + (CHAR(13) + CHAR(10)) +
									CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + 'RETURN 1' + (CHAR(13) + CHAR(10)) +
									CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + 'END' + (CHAR(13) + CHAR(10)) +
									CHAR(9) + CHAR(9) + CHAR(9) + 'IF (@xml2.value(''(/*/@*[local-name()=sql:variable("@attName")])[1]'',''varchar(MAX)'') <> @attValue)' + (CHAR(13) + CHAR(10)) +
									CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + 'BEGIN' + (CHAR(13) + CHAR(10)) +
									CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + 'RETURN 1' + (CHAR(13) + CHAR(10)) +
									CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + 'END' + (CHAR(13) + CHAR(10)) +
									CHAR(9) + CHAR(9) + CHAR(9) + 'SELECT' + CHAR(9) + '@cnt = @cnt + 1' + (CHAR(13) + CHAR(10)) +
									CHAR(9) + CHAR(9) + 'END' + (CHAR(13) + CHAR(10)) +
									'-- -------------------------------------------------------------' + (CHAR(13) + CHAR(10)) +
									'-- Match the number of child elements' + (CHAR(13) + CHAR(10)) +
									'-- -------------------------------------------------------------' + (CHAR(13) + CHAR(10)) +
									CHAR(9) + 'DECLARE @elCnt1 INT' + (CHAR(13) + CHAR(10)) +
									CHAR(9) + 'DECLARE @elCnt2 INT' + (CHAR(13) + CHAR(10)) +
									CHAR(9) + 'SELECT' + CHAR(9) + '@elCnt1 = @xml1.query(''count(/*/*)'').value(''.'',''INT'')' + (CHAR(13) + CHAR(10)) +
									CHAR(9) + 'SELECT' + CHAR(9) + '@elCnt2 = @xml2.query(''count(/*/*)'').value(''.'',''INT'')' + (CHAR(13) + CHAR(10)) +
									CHAR(9) + 'IF (@elCnt1 <> @elCnt2)' + (CHAR(13) + CHAR(10)) +
									CHAR(9) + CHAR(9) + 'BEGIN' + (CHAR(13) + CHAR(10)) +
									CHAR(9) + CHAR(9) + CHAR(9) + 'RETURN 1' + (CHAR(13) + CHAR(10)) +
									CHAR(9) + CHAR(9) + 'END' + (CHAR(13) + CHAR(10)) +
									'-- -------------------------------------------------------------' + (CHAR(13) + CHAR(10)) +
									'-- Start recursion for each child element' + (CHAR(13) + CHAR(10)) +
									'-- -------------------------------------------------------------' + (CHAR(13) + CHAR(10)) +
									CHAR(9) + 'SELECT' + CHAR(9) + '@cnt = 1' + (CHAR(13) + CHAR(10)) +
									CHAR(9) + 'DECLARE @x1 XML' + (CHAR(13) + CHAR(10)) +
									CHAR(9) + 'DECLARE @x2 XML' + (CHAR(13) + CHAR(10)) +
									CHAR(9) +' WHILE (@cnt <= @elCnt1)' + (CHAR(13) + CHAR(10)) +
									CHAR(9) + CHAR(9) + 'BEGIN' + (CHAR(13) + CHAR(10)) +
									CHAR(9) + CHAR(9) + CHAR(9) + 'SELECT' + CHAR(9) + '@x1 = @xml1.query(''/*/*[sql:variable("@cnt")]'')' + (CHAR(13) + CHAR(10)) +
									CHAR(9) + CHAR(9) + CHAR(9) + 'SELECT' + CHAR(9) + '@x2 = @xml2.query(''/*/*[sql:variable("@cnt")]'')' + (CHAR(13) + CHAR(10)) +
									CHAR(9) + CHAR(9) + CHAR(9) + 'IF dbo.CompareXml( @x1, @x2 ) = 1' + (CHAR(13) + CHAR(10)) +
									CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + 'BEGIN' + (CHAR(13) + CHAR(10)) +
									CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + 'RETURN 1' + (CHAR(13) + CHAR(10)) +
									CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + 'END' + (CHAR(13) + CHAR(10)) +
									CHAR(9) + CHAR(9) + CHAR(9) + 'SELECT' + CHAR(9) + '@cnt = @cnt + 1' + (CHAR(13) + CHAR(10)) +
									CHAR(9) + CHAR(9) + 'END' + (CHAR(13) + CHAR(10)) +
									(CHAR(13) + CHAR(10)) +
									CHAR(9) + 'RETURN @ret' + (CHAR(13) + CHAR(10)) +
									'END'

				SELECT	@SQLCXML = N'' + @SQLCXML

				EXEC @SQLFNExec @SQLCXML

			END

-- ======================
-- Create udf_GetTablePK
-- ======================
		IF (OBJECT_ID('dbo.udf_GetTablePK') IS NULL)
			BEGIN
				SELECT	@SQLGTPK =	'-- =============================================' + (CHAR(13) + CHAR(10)) +
									'-- Author:' + CHAR(9) + CHAR(9) + 'Chad Roesler' + (CHAR(13) + CHAR(10)) +
									'-- Create date: 6-26-2012' + (CHAR(13) + CHAR(10)) +
									'-- Description:' + CHAR(9) + 'Finds PK of a Table' + (CHAR(13) + CHAR(10)) +
									'-- Used for Generation of Dynamic SQL' + (CHAR(13) + CHAR(10)) +
									'-- =============================================' + (CHAR(13) + CHAR(10)) +
									'----------------------------' + (CHAR(13) + CHAR(10)) +
									'-- Modification: ' + (CHAR(13) + CHAR(10)) +
									'-- Modified By: Chad Roesler' + (CHAR(13) + CHAR(10)) +
									'-- Ticket Number: CR-000004' + (CHAR(13) + CHAR(10)) +
									'-- Modification Details: Initial Creation' + (CHAR(13) + CHAR(10)) +
									'-- Modification: This line needed for parsing reason' + (CHAR(13) + CHAR(10)) +
									'----------------------------' + (CHAR(13) + CHAR(10)) +
									'CREATE FUNCTION [dbo].[udf_GetTablePK] ' + (CHAR(13) + CHAR(10)) +
									'(' + (CHAR(13) + CHAR(10)) +
									CHAR(9) + '@TableName VARCHAR(50)' + (CHAR(13) + CHAR(10)) +
									')' + (CHAR(13) + CHAR(10)) +
									'RETURNS VARCHAR(100)' + (CHAR(13) + CHAR(10)) +
									'AS' + (CHAR(13) + CHAR(10)) +
									'BEGIN' + (CHAR(13) + CHAR(10)) +
									CHAR(9) + 'DECLARE @Return VARCHAR(100)' + (CHAR(13) + CHAR(10)) +
									CHAR(9) + 'SELECT' + CHAR(9) + '@Return = sc.name' + (CHAR(13) + CHAR(10)) +
									CHAR(9) + 'FROM' + CHAR(9) + 'sys.indexes si' + (CHAR(13) + CHAR(10)) +
									CHAR(9) + CHAR(9) + CHAR(9) + 'INNER JOIN sys.index_columns sic ON sic.object_id = si.object_id' + (CHAR(13) + CHAR(10)) +
									CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + 'AND sic.index_id = si.index_id' + (CHAR(13) + CHAR(10)) +
									CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + 'AND si.is_primary_key = 1' + (CHAR(13) + CHAR(10)) +
									CHAR(9) + CHAR(9) + CHAR(9) + 'INNER JOIN sys.columns sc ON sc.object_id = sic.object_id' + (CHAR(13) + CHAR(10)) +
									CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + 'AND sc.column_id = sic.column_id' + (CHAR(13) + CHAR(10)) +
									CHAR(9) + CHAR(9) + CHAR(9) + 'INNER JOIN sys.tables st ON st.object_id = sc.object_id' + (CHAR(13) + CHAR(10)) +
									CHAR(9) + 'WHERE st.name = @TableName' + (CHAR(13) + CHAR(10)) +
									CHAR(9) + 'RETURN' + CHAR(9) + '@Return' + (CHAR(13) + CHAR(10)) +
									'END'

				SELECT	@SQLGTPK = N'' + @SQLGTPK

				EXEC @SQLFNExec @SQLGTPK
			END

-- ======================
-- Create udf_ColumnType
-- ======================
		IF (OBJECT_ID('dbo.udf_ColumnType','FN') IS NULL)
			BEGIN
				SELECT	@SQLCT =	'-- =============================================' + (CHAR(13) + CHAR(10)) +
									'-- Author:' + CHAR(9) + CHAR(9) + 'Chad Roesler' + (CHAR(13) + CHAR(10)) +
									'-- Create date: 6-26-2012' + (CHAR(13) + CHAR(10)) +
									'-- Rev:' + CHAR(9) + CHAR(9) + CHAR(9) + '12-03-2012' + (CHAR(13) + CHAR(10)) +
									'-- Description:' + CHAR(9) + 'Finds Column Type From a Table' + (CHAR(13) + CHAR(10)) +
									'-- Used for Generation of Dynamic SQL' + (CHAR(13) + CHAR(10)) +
									'-- =============================================' + (CHAR(13) + CHAR(10)) +
									'----------------------------' + (CHAR(13) + CHAR(10)) +
									'-- Modification: ' + (CHAR(13) + CHAR(10)) +
									'-- Modified By: Chad Roesler' + (CHAR(13) + CHAR(10)) +
									'-- Ticket Number: CR-000006' + (CHAR(13) + CHAR(10)) +
									'-- Modification Details: Initial Creation' + (CHAR(13) + CHAR(10)) +
									'-- Modification: This line needed for parsing reason' + (CHAR(13) + CHAR(10)) +
									'----------------------------' + (CHAR(13) + CHAR(10)) +
									'CREATE FUNCTION [dbo].[udf_ColumnType] ' + (CHAR(13) + CHAR(10)) +
									'(' + (CHAR(13) + CHAR(10)) +
									CHAR(9) + '@TableName VARCHAR(50),' + (CHAR(13) + CHAR(10)) +
									CHAR(9) + '@ColumnName VARCHAR(50)' + (CHAR(13) + CHAR(10)) +
									')' + (CHAR(13) + CHAR(10)) +
									'RETURNS VARCHAR(100)' + (CHAR(13) + CHAR(10)) +
									'AS' + (CHAR(13) + CHAR(10)) +
									'BEGIN' + (CHAR(13) + CHAR(10)) +
									CHAR(9) + 'DECLARE @Return VARCHAR(100)' + (CHAR(13) + CHAR(10)) +
									CHAR(9) + 'SELECT' + CHAR(9) + '@Return = isc.DATA_TYPE' + (CHAR(13) + CHAR(10)) +
									CHAR(9) + 'FROM' + CHAR(9) + 'INFORMATION_SCHEMA.COLUMNS isc' + (CHAR(13) + CHAR(10)) +
									CHAR(9) + 'WHERE' + CHAR(9) + 'isc.TABLE_NAME = @TableName' + (CHAR(13) + CHAR(10)) +
									CHAR(9) + CHAR(9) + CHAR(9) + 'AND isc.COLUMN_NAME = @ColumnName' + (CHAR(13) + CHAR(10)) +
									CHAR(9) + 'RETURN' + CHAR(9) + '@Return' + (CHAR(13) + CHAR(10)) +
									'END'

				SELECT	@SQLCT = N'' + @SQLCT

				EXEC @SQLFNExec @SQLCT

			END

-- ======================
-- Create udf_ColumnByPosition
-- ======================
		IF (OBJECT_ID('dbo.udf_ColumnByPosition','FN') IS NULL)
			BEGIN
				SELECT	@SQLCBP =	'-- =============================================' + (CHAR(13) + CHAR(10)) +
									'-- Author:' + CHAR(9) + CHAR(9) + 'Chad Roesler' + (CHAR(13) + CHAR(10)) +
									'-- Create date: 6-26-2012' + (CHAR(13) + CHAR(10)) +
									'-- Rev:' + CHAR(9) + CHAR(9) + CHAR(9) + '12-03-2012' + (CHAR(13) + CHAR(10)) +
									'-- Description:' + CHAR(9) + 'Finds Column from a table' + (CHAR(13) + CHAR(10)) +
									'-- using column Number.' + (CHAR(13) + CHAR(10)) +
									'-- Used for Generation of Dynamic SQL' + (CHAR(13) + CHAR(10)) +
									'-- =============================================' + (CHAR(13) + CHAR(10)) +
									'----------------------------' + (CHAR(13) + CHAR(10)) +
									'-- Modification:' + (CHAR(13) + CHAR(10)) +
									'-- Modified By: Chad Roesler' + (CHAR(13) + CHAR(10)) +
									'-- Ticket Number: CR-000007' + (CHAR(13) + CHAR(10)) +
									'-- Modification Details: Initial Creation' + (CHAR(13) + CHAR(10)) +
									'-- Modification: This line needed for parsing reason' + (CHAR(13) + CHAR(10)) +
									'----------------------------' + (CHAR(13) + CHAR(10)) +
									'CREATE FUNCTION [dbo].[udf_ColumnByPosition] ' + (CHAR(13) + CHAR(10)) +
									'(' + (CHAR(13) + CHAR(10)) +
									CHAR(9) + '@TableName VARCHAR(50),' + (CHAR(13) + CHAR(10)) +
									CHAR(9) + '@OrdPos INT' + (CHAR(13) + CHAR(10)) +
									')' + (CHAR(13) + CHAR(10)) +
									'RETURNS VARCHAR(100)' + (CHAR(13) + CHAR(10)) +
									'AS' + (CHAR(13) + CHAR(10)) +
									'BEGIN' + (CHAR(13) + CHAR(10)) +
									CHAR(9) + 'DECLARE @Return VARCHAR(100)' + (CHAR(13) + CHAR(10)) +
									CHAR(9) + 'SELECT' + CHAR(9) + '@Return = isc.COLUMN_NAME' + (CHAR(13) + CHAR(10)) +
									CHAR(9) + 'FROM' + CHAR(9) + 'INFORMATION_SCHEMA.COLUMNS isc' + (CHAR(13) + CHAR(10)) +
									CHAR(9) + 'WHERE' + CHAR(9) + 'isc.TABLE_NAME = @TableName' + (CHAR(13) + CHAR(10)) +
									CHAR(9) + CHAR(9) + CHAR(9) + 'AND isc.ORDINAL_POSITION = @OrdPos' + (CHAR(13) + CHAR(10)) +
									CHAR(9) + 'RETURN' + CHAR(9) + '@Return' + (CHAR(13) + CHAR(10)) +
									'END'

				SELECT	@SQLCBP = N'' + @SQLCBP

				EXEC @SQLFNExec @SQLCBP

			END

-- ======================
-- Create Diff Table Name
-- ======================
		SELECT @DiffTable = '##DIFF' + @TableOne + @TableTwo

-- =====================
-- Insert to Global Temp
-- =====================
		SELECT	@SQLDrop = 'IF OBJECT_ID(''tempdb.dbo.' + @DiffTable + ''') IS NOT NULL' + (CHAR(13) + CHAR(10)) + CHAR(9) +	'DROP TABLE ##DIFF' + @TableOne + @TableTwo
		EXEC (@SQLDrop)
		SELECT	@SQLGloIn = 'INTO' + CHAR(9) + @DiffTable
		SELECT	@SQLGlobal = 'SELECT' + CHAR(9) + '*' + (CHAR(13) + CHAR(10)) + 'FROM' + CHAR(9) + @DiffTable + ' d'

-- =====================
-- Declare Primary Key
-- =====================
		SELECT	@PriKey = dbo.udf_GetTablePK(@RootTable)

-- =====================
-- Decare Column Count
-- =====================
		SELECT 	@Count = COUNT(*)
		FROM	sys.tables t
				INNER JOIN sys.columns c ON c.object_id = t.object_id
		WHERE	t.name = @RootTable

-- =====================
-- Partial Table Join Type Declaration
-- =====================
		IF (@PartialTable = 1)
			BEGIN
				SELECT	@JoinType = 'LEFT'
			END
		ELSE
			BEGIN
				SELECT	@JoinType = 'FULL'
			END
-- =====================
-- Consider Partial Table
-- =====================
		IF (@PartialTable = 0)
			BEGIN
				CREATE TABLE #PTRowCnt
					(
					BkupRowCnt DECIMAL(10,4),
					OrigRowCnt DECIMAL(10,4),
					RowPercent DECIMAL(10,4)
					)
				SELECT	@SQLRowCnt = 'INSERT INTO #PTRowCnt' + (CHAR(13) + CHAR(10)) +
									 CHAR(9) + '(' + (CHAR(13) + CHAR(10)) +
									 CHAR(9) + 'BkupRowCnt' + (CHAR(13) + CHAR(10)) +
									 CHAR(9) + ')' + (CHAR(13) + CHAR(10)) +
									 'SELECT' + CHAR(9) + 'COUNT(*)' + (CHAR(13) + CHAR(10)) +
									 'FROM' + CHAR(9) + @TableOne + (CHAR(13) + CHAR(10)) +
									 'UPDATE' + CHAR(9) + 'prc' + (CHAR(13) + CHAR(10)) +
									 'SET' + CHAR(9) + CHAR(9) + 'prc.OrigRowCnt = orig.RCnt' + (CHAR(13) + CHAR(10)) +
									 'FROM' + CHAR(9) + '#PTRowCnt prc' + (CHAR(13) + CHAR(10)) +
									 CHAR(9) + CHAR(9) + 'CROSS JOIN (SELECT' + CHAR(9) + 'COUNT(*) AS RCnt' + (CHAR(13) + CHAR(10)) +
									 CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + 'FROM' + CHAR(9) + @TableTwo + ' origcnt ) AS orig' + (CHAR(13) + CHAR(10)) +
									 'UPDATE' + CHAR(9) + 'prc' + (CHAR(13) + CHAR(10)) +
									 'SET' + CHAR(9) + CHAR(9) + 'prc.RowPercent = NULLIF(prc.BkupRowCnt,0) / NULLIF(prc.OrigRowCnt,0)' + (CHAR(13) + CHAR(10)) +
									 'FROM' + CHAR(9) + '#PTRowCnt prc'
				EXEC (@SQLRowCnt)
				IF EXISTS ( SELECT	*
							FROM	#PTRowCnt prc
							WHERE	prc.RowPercent < .1 )
					BEGIN
						PRINT 'Backup Table may be a Partial Table, are you sure you want to run with @PartialTable = 0?'
					END
				DROP TABLE #PTRowCnt
			END
-- =====================
-- SELECT Text
-- =====================
		SELECT 	@SQLSelect = 'SELECT' + CHAR(9) + 'CASE WHEN (orig.' + @PriKey + ' IS NOT NULL )' + (CHAR(13) + CHAR(10)) + CHAR(9) + CHAR(9) + CHAR(9) + ' THEN CASE WHEN (bkup.' + @PriKey + ' IS NOT NULL)' + (CHAR(13) + CHAR(10)) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + '   THEN ''Changed Row'' ' + (CHAR(13) + CHAR(10)) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + '   ELSE ''Added Row'''+ (CHAR(13) + CHAR(10)) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + CHAR(9) + '   END' + (CHAR(13) + CHAR(10)) + CHAR(9) + CHAR(9) + CHAR(9) + ' ELSE ''Deleted Row''' + (CHAR(13) + CHAR(10)) + CHAR(9) + CHAR(9) + CHAR(9) + ' END AS ModificationType'
		SELECT 	@Row = 1
		WHILE 	(@Count >= @Row)
			BEGIN
				SELECT 	@SQLSelect = @SQLSelect + ',' + (CHAR(13) + CHAR(10)) + CHAR(9) + CHAR(9) + 'bkup.'+ dbo.udf_ColumnByPosition(@RootTable,@Row) + ' AS Backup_'+ dbo.udf_ColumnByPosition(@RootTable,@Row) + ',' + (CHAR(13) + CHAR(10)) + CHAR(9) + CHAR(9) + 'orig.'+ dbo.udf_ColumnByPosition(@RootTable,@Row) + ' AS Orig_'+ dbo.udf_ColumnByPosition(@RootTable,@Row)
				SELECT 	@Row = @Row + 1
			END

-- =====================
-- FROM Text
-- =====================
		SELECT 	@SQLFrom = 'FROM' + CHAR(9) + @TableOne + ' AS bkup' + (CHAR(13) + CHAR(10)) + CHAR(9) + CHAR(9) + @JoinType + ' JOIN ' + @TableTwo + ' AS orig ON orig.' + @PriKey + ' = bkup.' + @PriKey + ' '

-- =====================
-- WHERE1 Text
-- =====================
		SELECT 	@SQLWhere1 = 'WHERE ' + CHAR(9) + '(	orig.' + dbo.udf_ColumnByPosition(@RootTable,1) + ' <> bkup.' + dbo.udf_ColumnByPosition(@RootTable,1) + ' '
		SELECT 	@Row = 2
		WHILE 	(@Count >= @Row)
			BEGIN
				IF (dbo.udf_ColumnType(@RootTable,dbo.udf_ColumnByPosition(@RootTable,@Row)) = 'XML')
					BEGIN
						IF (@XML = 1)
							BEGIN
								SELECT	@SQLWhere1 = @SQLWhere1 + (CHAR(13) + CHAR(10)) + CHAR(9) + CHAR(9) + CHAR(9) + 'OR dbo.CompareXML(orig.' + dbo.udf_ColumnByPosition(@RootTable,@Row) + ',bkup.' + dbo.udf_ColumnByPosition(@RootTable,@Row) + ') = 1'
								SELECT 	@Row = @Row + 1
							END
						ELSE
							BEGIN
								SELECT 	@Row = @Row + 1
							END
					END
				ELSE IF (dbo.udf_ColumnType(@RootTable,dbo.udf_ColumnByPosition(@RootTable,@Row)) = 'IMAGE')
					BEGIN
						SELECT 	@SQLWhere1 = @SQLWhere1 + (CHAR(13) + CHAR(10)) + CHAR(9) + CHAR(9) + CHAR(9) + 'OR CONVERT(VARBINARY(MAX),orig.' + dbo.udf_ColumnByPosition(@RootTable,@Row) + ') <> CONVERT(VARBINARY(MAX),bkup.' + dbo.udf_ColumnByPosition(@RootTable,@Row) + ') '
						SELECT 	@Row = @Row + 1
					END
				ELSE
					BEGIN
						SELECT 	@SQLWhere1 = @SQLWhere1 + (CHAR(13) + CHAR(10)) + CHAR(9) + CHAR(9) + CHAR(9) + 'OR orig.' + dbo.udf_ColumnByPosition(@RootTable,@Row) + ' <> bkup.' + dbo.udf_ColumnByPosition(@RootTable,@Row) + ' '
						SELECT 	@Row = @Row + 1
					END
			END
		SELECT 	@SQLWhere1 = @SQLWhere1 + (CHAR(13) + CHAR(10)) + CHAR(9) + CHAR(9) + ')'
-- =====================
-- WHERE2
-- Insert or Deleted Check
-- =====================
		SELECT	@SQLWhere2 = CHAR(9) + CHAR(9) + 'OR ( orig.' + @PriKey + ' IS NULL)' + (CHAR(13) + CHAR(10)) + CHAR(9) + CHAR(9) + 'OR ( bkup.' + @PriKey + ' IS NULL) '
-- =====================
-- WHERE3
-- Update Check
-- Checks if rows have been modified to NULL
-- =====================
		SELECT 	@SQLWhere3 = CHAR(9) + CHAR(9) + 'OR ((orig.' + dbo.udf_ColumnByPosition(@RootTable,1) + ' IS NULL AND bkup.' + dbo.udf_ColumnByPosition(@RootTable,1) + ' IS NOT NULL) OR (bkup.' + dbo.udf_ColumnByPosition(@RootTable,1) + ' IS NULL AND orig.' + dbo.udf_ColumnByPosition(@RootTable,1) + ' IS NOT NULL)'
		SELECT 	@Row = 2
		WHILE 	(@Count >= @Row)
			BEGIN
				SELECT 	@SQLWhere3 = @SQLWhere3 + (CHAR(13) + CHAR(10)) + CHAR(9) + CHAR(9) + CHAR(9) + ' OR (orig.' + dbo.udf_ColumnByPosition(@RootTable,@Row) + ' IS NULL AND bkup.' + dbo.udf_ColumnByPosition(@RootTable,@Row) + ' IS NOT NULL) OR (bkup.' + dbo.udf_ColumnByPosition(@RootTable,@Row) + ' IS NULL AND orig.' + dbo.udf_ColumnByPosition(@RootTable,@Row) + ' IS NOT NULL) '
				SELECT 	@Row = @Row + 1
			END
		SELECT 	@SQLWhere3 = @SQLWhere3 + (CHAR(13) + CHAR(10)) + CHAR(9) + CHAR(9) + '   )'

-- =====================
-- Exec of Creation of Diff Table SQL
-- =====================
		EXEC (@SQLSelect + ' ' + @SQLGloIn + ' ' + @SQLFrom + ' ' + @SQLWhere1 + ' ' + @SQLWhere2 + ' ' + @SQLWhere3)

-- =====================
-- UPDATE Diferences
-- =====================
		IF	(@Update = 1)
			BEGIN
				CREATE	TABLE	#UpdateColumnDiff
								(
								RowID INT IDENTITY(1,1),
								ColumnName VARCHAR(255)
								)
				SELECT @Row = 2
				WHILE	@Count >= @Row
					BEGIN
						IF (dbo.udf_ColumnType(@RootTable,dbo.udf_ColumnByPosition(@RootTable,@Row)) = 'XML')
							BEGIN
								IF (@XML = 1)
									BEGIN
										SELECT	@SQLUpColL = 'IF EXISTS (SELECT * FROM ' + @DiffTable + ' d  WHERE d.ModificationType = ''Changed Row'' AND dbo.CompareXML(d.orig_' + dbo.udf_ColumnByPosition(@RootTable,@Row) + ',d.backup_' + dbo.udf_ColumnByPosition(@RootTable,@Row) + ') = 1)' + (CHAR(13) + CHAR(10))
									END
							END
						ELSE IF (dbo.udf_ColumnType(@RootTable,dbo.udf_ColumnByPosition(@RootTable,@Row)) = 'IMAGE')
							BEGIN
								SELECT	@SQLUpColL = 'IF EXISTS (SELECT * FROM ' + @DiffTable + ' d  WHERE d.ModificationType = ''Changed Row'' AND CONVERT(VARBINARY(MAX),d.orig_' + dbo.udf_ColumnByPosition(@RootTable,@Row) + ') <> CONVERT(VARBINARY(MAX),d.backup_' + dbo.udf_ColumnByPosition(@RootTable,@Row) + '))' + (CHAR(13) + CHAR(10))
							END
						ELSE
							BEGIN
								SELECT	@SQLUpColL = 'IF EXISTS (SELECT * FROM ' + @DiffTable + ' d  WHERE d.ModificationType = ''Changed Row'' AND d.orig_' + dbo.udf_ColumnByPosition(@RootTable,@Row) + ' <> d.backup_' + dbo.udf_ColumnByPosition(@RootTable,@Row) + ')' + (CHAR(13) + CHAR(10))
							END
						SELECT	@SQLUpColL = @SQLUpColL + CHAR(9) + 'BEGIN' + (CHAR(13) + CHAR(10))
						SELECT	@SQLUpColL = @SQLUpColL + CHAR(9) + CHAR(9) + 'INSERT INTO #UpdateColumnDiff' + (CHAR(13) + CHAR(10))
						SELECT	@SQLUpColL = @SQLUpColL + CHAR(9) + CHAR(9) + 'SELECT ''' + dbo.udf_ColumnByPosition(@RootTable,@Row) + '''' + (CHAR(13) + CHAR(10))
						SELECT	@SQLUpColL = @SQLUpColL + CHAR(9) + 'END'
						EXEC (@SQLUpColL)
						SELECT	@Row = @Row + 1
					END
			END

-- =====================
-- UPDATE Text
-- =====================
		IF	(@Update = 1)
			BEGIN
				SELECT	@UpCount = MAX(ucd.RowID)
				FROM	#UpdateColumnDiff ucd
				SELECT	@UpCol = ucd.ColumnName
				FROM	#UpdateColumnDiff ucd
				WHERE	ucd.RowID = 1
				SELECT	@SQLUpTable = 'CREATE TABLE #' + @PriKey + '_UpdateOutput' + (CHAR(13) + CHAR(10)) + CHAR(9) + CHAR(9) + '(' + (CHAR(13) + CHAR(10)) + CHAR(9) + CHAR(9) + @PriKey + ' ' + dbo.udf_ColumnType(@RootTable,@PriKey) + (CHAR(13) + CHAR(10)) + CHAR(9) + CHAR(9) + ')' + (CHAR(13) + CHAR(10))
				SELECT	@SQLUpdate = 'UPDATE' + CHAR(9) + 'orig' + (CHAR(13) + CHAR(10)) + 'SET ' + CHAR(9)
				SELECT	@SQLUpdate = @SQLUpdate + 'orig.' + @UpCol + ' = d.Backup_' + @UpCol + ''
				SELECT	@Row = 2
				WHILE	(@UpCount >= @Row)
					BEGIN
						SELECT	@UpCol = ucd.ColumnName
						FROM	#UpdateColumnDiff ucd
						WHERE	ucd.RowID = @Row
						SELECT	@SQLUpdate = @SQLUpdate + ',' + (CHAR(13) + CHAR(10)) + CHAR(9) + CHAR(9) + 'orig.' + @UpCol + ' = d.Backup_' + @UpCol + ''
						SELECT	@Row = @Row + 1
					END
				SELECT	@SQLUpOut = (CHAR(13) + CHAR(10)) + 'OUTPUT' + CHAR(9) + 'INSERTED.' + @PriKey + ' INTO #' + @PriKey + '_UpdateOutput'
				SELECT	@SQLUpFrom = (CHAR(13) + CHAR(10)) + 'FROM ' + CHAR(9) + @TableTwo + ' orig' + (CHAR(13) + CHAR(10)) + CHAR(9) + CHAR(9) + 'INNER JOIN ' + @DiffTable + ' d ON d.Backup_'+ @PriKey + ' = orig.' + @PriKey + ''
				SELECT	@SQLUpWhere = (CHAR(13) + CHAR(10)) + 'WHERE' + CHAR(9) + 'd.ModificationType = ''Changed Row'''
				DROP TABLE #UpdateColumnDiff
			END

-- =====================
-- INSERT Text
-- =====================
		IF	(@Insert = 1)
			BEGIN
				SELECT	@SQLInTable = 'CREATE TABLE #' + @PriKey + '_InsertOutput' + (CHAR(13) + CHAR(10)) + CHAR(9) + CHAR(9) + '(' + (CHAR(13) + CHAR(10)) + CHAR(9) + CHAR(9) + @PriKey + ' ' + dbo.udf_ColumnType(@RootTable,@PriKey) + (CHAR(13) + CHAR(10)) + CHAR(9) + CHAR(9) + ')' + (CHAR(13) + CHAR(10))
				SELECT	@SQLInsert = 'INSERT INTO ' + @TableTwo + (CHAR(13) + CHAR(10)) + CHAR(9) + CHAR(9) + '(' + (CHAR(13) + CHAR(10)) + CHAR(9) + CHAR(9)
				SELECT	@SQLInsert = @SQLInsert + dbo.udf_ColumnByPosition(@RootTable,2)
				SELECT	@Row = 3
				WHILE	(@Count >= @Row)
					BEGIN
						SELECT	@SQLInsert = @SQLInsert + ',' + (CHAR(13) + CHAR(10)) + CHAR(9) + CHAR(9) + dbo.udf_ColumnByPosition(@RootTable,@Row)
						SELECT	@Row = @Row + 1
					END
				SELECT	@SQLInOut = 'OUTPUT' + CHAR(9) + 'INSERTED.' + @PriKey + ' INTO #' + @PriKey + '_InsertOutput' + (CHAR(13) + CHAR(10))
				SELECT	@SQLInsert = @SQLInsert + (CHAR(13) + CHAR(10)) + CHAR(9) + CHAR(9) + ')' + (CHAR(13) + CHAR(10))
				SELECT	@SQLInSel = 'SELECT' + CHAR(9) + 'd.Backup_' + dbo.udf_ColumnByPosition(@RootTable,2)
				SELECT	@Row = 3
				WHILE	(@Count >= @Row)
					BEGIN
						SELECT	@SQLInSel = @SQLInSel + ',' + (CHAR(13) + CHAR(10)) + CHAR(9) + CHAR(9) + 'd.Backup_' + dbo.udf_ColumnByPosition(@RootTable,@Row)
						SELECT	@Row = @Row + 1
					END
				SELECT	@SQLInFrom = (CHAR(13) + CHAR(10)) + 'FROM ' + CHAR(9) + @DiffTable + ' d'
				SELECT	@SQLInWhere = (CHAR(13) + CHAR(10)) + 'WHERE' + CHAR(9) + 'd.ModificationType = ''Deleted Row'''

				IF (OBJECT_ID('tempdb..##ConstrainedTables') IS NOT NULL)
					BEGIN
						DROP TABLE ##ConstrainedTables
					END

				CREATE TABLE ##ConstrainedTables
					(
					TableName VARCHAR(MAX),
					BackupTableName VARCHAR(MAX),
					SQLToExec VARCHAR(MAX)
					)

				INSERT INTO ##ConstrainedTables
					(
					TableName,
					BackupTableName
					)
				SELECT	st2.name,
						REPLACE(@TableOne,@RootTable,st2.name)
				FROM	sys.foreign_key_columns fk
						INNER JOIN sys.tables st ON st.Object_id = fk.Referenced_object_id
						INNER JOIN sys.tables st2 ON st2.Object_id = fk.Parent_object_id
													 AND st2.Object_ID <> st.Object_id
				WHERE st.Name = @RootTable

				UPDATE	ct
				SET		ct.SQLToExec = ISNULL('EXEC UTIL_BackUpTableDiff ' + st.Name + ', ' + @TableTwo + ', ' + CONVERT(VARCHAR(MAX),@SkipRootTableCheck) + ', ' + CONVERT(VARCHAR(MAX),@XML) + ', ' + CONVERT(VARCHAR(MAX),@PartialTable) + ', ' + CONVERT(VARCHAR(MAX),@Insert) + ', ' + CONVERT(VARCHAR(MAX),@Update) + ', ' + CONVERT(VARCHAR(MAX),@Delete) + ', ' + CONVERT(VARCHAR(MAX),@Debug) ,'Table Was Never Backed Up')
				FROM	##ConstrainedTables ct
						LEFT JOIN Sys.tables st ON st.name = ct.BackupTableName

			END

-- =====================
-- DELETE Text
-- =====================
		IF (@Delete = 1)
			BEGIN
				SELECT	@SQLDeTable = 'CREATE TABLE #' + @PriKey + '_DeleteOutput' + (CHAR(13) + CHAR(10)) + CHAR(9) + CHAR(9) + '(' + (CHAR(13) + CHAR(10)) + CHAR(9) + CHAR(9) + @PriKey + ' ' + dbo.udf_ColumnType(@RootTable,@PriKey) + (CHAR(13) + CHAR(10)) + CHAR(9) + CHAR(9) + ')' + (CHAR(13) + CHAR(10))
				SELECT	@SQLDelete = 'DELETE ' + CHAR(9) + 'orig'
				SELECT	@SQLDeOut = (CHAR(13) + CHAR(10)) + 'OUTPUT' + CHAR(9) + 'DELETED.' + @PriKey + ' INTO #' + @PriKey + '_DeleteOutput'
				SELECT	@SQLDeFrom = (CHAR(13) + CHAR(10)) + 'FROM ' + CHAR(9) + @TableTwo + ' orig' + (CHAR(13) + CHAR(10)) + CHAR(9) + CHAR(9) + 'INNER JOIN ' + @DiffTable + ' d ON d.Orig_'+ @PriKey + ' = orig.' + @PriKey + ''
				SELECT	@SQLDeWhere = (CHAR(13) + CHAR(10)) + 'WHERE' + CHAR(9) + 'd.ModificationType = ''Added Row'''
			END

-- =====================
-- BackUp Text
-- =====================
		SELECT	@SQLBackUp = 'UTIL_BackupTable ' + @TableTwo

-- =====================
-- Debug/Exec
-- =====================
		IF (@Debug = 1)
			BEGIN
				PRINT '/*********************'
				PRINT '      DEBUG INFO'
				PRINT '*********************/'
				PRINT '--===================='
				PRINT 'Database Name: ' + CHAR(9) + @DBName
				PRINT 'TableOne: ' + CHAR(9) + CHAR(9) + @TableOne
				PRINT 'TableTwo: ' + CHAR(9) + CHAR(9) + @TableTwo
				PRINT 'RootTable: ' + CHAR(9) + CHAR(9) + @RootTable
				PRINT 'PrimaryKey: ' + CHAR(9) + @PriKey
				PRINT 'ColumnCount: ' + CHAR(9) + CONVERT(VARCHAR(MAX),@Count)
				PRINT 'DiffTableName: ' + CHAR(9) + @DiffTable
				PRINT 'SkipRootCheck?:' + CHAR(9) + CASE WHEN @SkipRootTableCheck= 1
														 THEN 'Yes'
														 ELSE 'No'
														 END
				PRINT 'PartialTable?:' + CHAR(9) + CASE WHEN @PartialTable = 1
														THEN 'Yes'
														ELSE 'No'
														END
				IF (@PartialTable = 0)
					BEGIN
						PRINT 'Possible PT?:' + CHAR(9) + CASE WHEN @PossiblePT = 1
															   THEN 'Yes'
															   ELSE 'No'
															   END
					END
				PRINT 'XML Diffed?: ' + CHAR(9) + CASE WHEN @XML = 1
													   THEN 'Yes'
													   ELSE 'No'
													   END
				IF (@PartialTable = 0)
					BEGIN
						PRINT '--===================='
						PRINT @SQLRowCnt
					END
				PRINT '--===================='
				PRINT @SQLSelect
				PRINT @SQLGloIn
				PRINT @SQLFROM
				PRINT @SQLWhere1
				PRINT @SQLWhere2
				PRINT @SQLWhere3
				PRINT '--===================='
				PRINT @SQLGlobal
				PRINT '--===================='
				PRINT @SQLDrop
				PRINT '--===================='
				IF	(@Update = 1)
					BEGIN
						PRINT '/*********************'
						PRINT '        UPDATE'
						PRINT '*********************/'
						PRINT '/*********************'
						PRINT @SQLBackUp
						PRINT @SQLUpTable
						PRINT @SQLUpdate
						PRINT @SQLUpOut
						PRINT @SQLUpFrom
						PRINT @SQLUpWhere
						PRINT '*********************/'
					END
				IF	(@Insert = 1)
					BEGIN
						PRINT '/*********************'
						PRINT '        INSERT'
						PRINT '*********************/'
						PRINT '/*********************'
						PRINT @SQLBackUp
						PRINT @SQLInTable
						PRINT @SQLInsert
						PRINT @SQLInOut
						PRINT @SQLInSel
						PRINT @SQLInFrom
						PRINT @SQLInWhere
						PRINT '*********************/'
					END
				IF	(@Delete = 1)
					BEGIN
						PRINT '/*********************'
						PRINT '        DELETE'
						PRINT '*********************/'
						PRINT '/*********************'
						PRINT @SQLBackUp
						PRINT @SQLDeTable
						PRINT @SQLDelete
						PRINT @SQLDeOut
						PRINT @SQLDeFrom
						PRINT @SQLDeWhere
						PRINT '*********************/'
					END
			END
		ELSE
			BEGIN
				IF	(@Update = 1)
					BEGIN
						PRINT '/*********************'
						PRINT '        UPDATE'
						PRINT '*********************/'
						PRINT @SQLBackUp
						PRINT (CHAR(13) + CHAR(10))
						PRINT (@SQLUpTable + @SQLUpdate + @SQLUpOut + @SQLUpFrom + @SQLUpWhere)
						EXEC ('SELECT * ' + @SQLUpFrom + @SQLUpWhere)
					END
				IF	(@Insert = 1)
					BEGIN
						PRINT '/*********************'
						PRINT '        INSERT'
						PRINT '*********************/'
						PRINT 'Please check the second select statment for tables that may need to have inserts run on them'
						PRINT @SQLBackUp
						PRINT (CHAR(13) + CHAR(10))
						PRINT (@SQLInTable + @SQLInsert + @SQLInOut + @SQLInSel + @SQLInFrom + @SQLInWhere)
						EXEC ('SELECT * ' + @SQLInFrom + @SQLInWhere)
						SELECT	*
						FROM	##ConstrainedTables
					END
				IF	(@Delete = 1)
					BEGIN
						PRINT '/*********************'
						PRINT '        DELETE'
						PRINT '*********************/'
						PRINT @SQLBackUp
						PRINT (CHAR(13) + CHAR(10))
						PRINT (@SQLDeTable + @SQLDelete + @SQLDeOut + @SQLDeFROM + @SQLDeWhere)
						EXEC ('SELECT * ' + @SQLDeFROM + @SQLDeWhere)
					END
				IF	(@Update = 0 AND @Insert = 0 AND @Update = 0)
					BEGIN
						EXEC (@SQLGlobal)
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
