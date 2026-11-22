SET NOCOUNT ON;
SET XACT_ABORT ON;
IF @DatabaseName NOT IN (N'nito_superDb',N'nito_SomeApps')
    THROW 50010,'Unexpected seed database.',1;
IF COALESCE(HAS_DBACCESS(@DatabaseName),0)<>1
    THROW 50011,'Seed database does not exist or is inaccessible.',1;
IF @@TRANCOUNT=0 THROW 50012,'Seed must run in a transaction.',1;
DECLARE @LockResult int;
EXEC @LockResult=sys.sp_getapplock @Resource=N'ArchiveScenarioTest.Seed',
    @LockMode=N'Exclusive',@LockOwner=N'Transaction',@LockTimeout=10000;
IF @LockResult<0 THROW 50013,'Could not acquire seed lock.',1;

DECLARE @Edges TABLE (
    Position int PRIMARY KEY, RootNumber int, ParentName sysname, ChildName sysname, ChildColumn sysname
);
INSERT @Edges VALUES
    (1,1,N'Root01',N'R01_Items',N'ParentId'),
    (2,2,N'Root02',N'R02_Items',N'ParentId'),
    (3,2,N'R02_Items',N'R02_Details',N'ParentId'),
    (4,3,N'Root03',N'R03_A',N'ParentId'),
    (5,3,N'R03_A',N'R03_B',N'ParentId'),
    (6,3,N'R03_B',N'R03_C',N'ParentId'),
    (7,4,N'Root04',N'R04_A',N'ParentId'),
    (8,4,N'Root04',N'R04_B',N'ParentId'),
    (9,4,N'Root04',N'R04_C',N'ParentId'),
    (10,5,N'Root05',N'R05_Left',N'ParentId'),
    (11,5,N'Root05',N'R05_Right',N'ParentId'),
    (12,5,N'R05_Left',N'R05_Shared',N'LeftId'),
    (13,5,N'R05_Right',N'R05_Shared',N'RightId'),
    (14,6,N'Root06',N'R06_A',N'ParentId'),
    (15,6,N'R06_A',N'R06_B',N'ParentId'),
    (16,6,N'R06_B',N'R06_C',N'ParentId'),
    (17,6,N'R06_C',N'R06_D',N'ParentId'),
    (18,7,N'Root07',N'R07_A',N'ParentId'),
    (19,7,N'Root07',N'R07_B',N'ParentId'),
    (20,7,N'R07_A',N'R07_A1',N'ParentId'),
    (21,7,N'R07_A',N'R07_A2',N'ParentId'),
    (22,7,N'R07_B',N'R07_B1',N'ParentId'),
    (23,8,N'Root08',N'R08_A',N'ParentId'),
    (24,8,N'Root08',N'R08_B',N'ParentId'),
    (25,8,N'Root08',N'R08_C',N'ParentId');

DECLARE @Nodes TABLE (Name sysname PRIMARY KEY, Position int, IsRoot bit);
DECLARE @Number int=1;
WHILE @Number<=40
BEGIN
    INSERT @Nodes VALUES(N'Root'+RIGHT(N'0'+CONVERT(nvarchar(2),@Number),2),0,1);
    SET @Number+=1;
END;
INSERT @Nodes
SELECT ChildName,MIN(Position),0 FROM @Edges GROUP BY ChildName;

DECLARE @Database nvarchar(258)=QUOTENAME(@DatabaseName),@Sql nvarchar(max);
SET @Sql=N'USE '+@Database+N'; IF SCHEMA_ID(N''ArchiveScenarioTest'') IS NULL EXEC(N''CREATE SCHEMA ArchiveScenarioTest'');';
EXEC sys.sp_executesql @Sql;

DECLARE @Name sysname,@IsRoot bit,@Columns nvarchar(max),@Constraints nvarchar(max);
DECLARE CreateNodes CURSOR LOCAL FAST_FORWARD FOR SELECT Name,IsRoot FROM @Nodes ORDER BY Position,Name;
OPEN CreateNodes;
FETCH NEXT FROM CreateNodes INTO @Name,@IsRoot;
WHILE @@FETCH_STATUS=0
BEGIN
    SET @Columns=N'';
    SET @Constraints=N'';
    IF @IsRoot=1 SET @Columns=N',CreatedAt datetime2(7) NOT NULL';
    ELSE
    BEGIN
        SELECT @Columns=(
            SELECT N','+QUOTENAME(e.ChildColumn)+N' int NOT NULL'
            FROM @Edges e WHERE e.ChildName=@Name ORDER BY e.Position
            FOR XML PATH(''),TYPE).value('.','nvarchar(max)');
        SELECT @Constraints=(
            SELECT N',CONSTRAINT '+QUOTENAME(N'FK_'+e.ChildName+N'_'+e.ChildColumn)+
                N' FOREIGN KEY ('+QUOTENAME(e.ChildColumn)+N') REFERENCES ArchiveScenarioTest.'+
                QUOTENAME(e.ParentName)+N'(Id) ON DELETE NO ACTION'
            FROM @Edges e WHERE e.ChildName=@Name ORDER BY e.Position
            FOR XML PATH(''),TYPE).value('.','nvarchar(max)');
    END;
    SET @Sql=N'USE '+@Database+N'; IF OBJECT_ID(N''ArchiveScenarioTest.'+@Name+N''',N''U'') IS NULL BEGIN
        CREATE TABLE ArchiveScenarioTest.'+QUOTENAME(@Name)+N'(
            Id int NOT NULL PRIMARY KEY,Payload nvarchar(100) NOT NULL'+@Columns+@Constraints+N');';
    IF @IsRoot=0
        SELECT @Sql=@Sql+(
            SELECT N' CREATE INDEX '+QUOTENAME(N'IX_'+e.ChildName+N'_'+e.ChildColumn)+
                N' ON ArchiveScenarioTest.'+QUOTENAME(@Name)+N'('+QUOTENAME(e.ChildColumn)+N');'
            FROM @Edges e WHERE e.ChildName=@Name ORDER BY e.Position
            FOR XML PATH(''),TYPE).value('.','nvarchar(max)');
    SET @Sql+=N' END;';
    EXEC sys.sp_executesql @Sql;
    FETCH NEXT FROM CreateNodes INTO @Name,@IsRoot;
END;
CLOSE CreateNodes;
DEALLOCATE CreateNodes;

-- Clear only this seed's tables, starting at the deepest dependencies.
DECLARE ClearNodes CURSOR LOCAL FAST_FORWARD FOR SELECT Name FROM @Nodes ORDER BY Position DESC,Name;
OPEN ClearNodes;
FETCH NEXT FROM ClearNodes INTO @Name;
WHILE @@FETCH_STATUS=0
BEGIN
    SET @Sql=N'DELETE FROM '+@Database+N'.ArchiveScenarioTest.'+QUOTENAME(@Name)+N';';
    EXEC sys.sp_executesql @Sql;
    FETCH NEXT FROM ClearNodes INTO @Name;
END;
CLOSE ClearNodes;
DEALLOCATE ClearNodes;

DECLARE @Values nvarchar(max);
DECLARE FillNodes CURSOR LOCAL FAST_FORWARD FOR SELECT Name,IsRoot FROM @Nodes ORDER BY Position,Name;
OPEN FillNodes;
FETCH NEXT FROM FillNodes INTO @Name,@IsRoot;
WHILE @@FETCH_STATUS=0
BEGIN
    SET @Columns=N'';
    SET @Values=N'';
    IF @IsRoot=1
    BEGIN
        SET @Columns=N',CreatedAt';
        SET @Values=N',DATEADD(day,CASE WHEN v.Id=1 THEN -60 WHEN v.Id=2 THEN -59 ELSE 0 END,CONVERT(date,SYSDATETIME()))';
        -- Root39 has recent rows only. Root40 remains empty.
        IF @Name=N'Root39' SET @Values=N',CONVERT(date,SYSDATETIME())';
    END
    ELSE
    BEGIN
        SELECT @Columns=(
            SELECT N','+QUOTENAME(e.ChildColumn) FROM @Edges e WHERE e.ChildName=@Name
            ORDER BY e.Position FOR XML PATH(''),TYPE).value('.','nvarchar(max)');
        SELECT @Values=(
            SELECT N',CASE WHEN v.Id=3 THEN 3 ELSE 1 END' FROM @Edges e WHERE e.ChildName=@Name
            ORDER BY e.Position FOR XML PATH(''),TYPE).value('.','nvarchar(max)');
    END;
    IF @Name<>N'Root40'
    BEGIN
        SET @Sql=N'INSERT '+@Database+N'.ArchiveScenarioTest.'+QUOTENAME(@Name)+N'(Id,Payload'+@Columns+
            N') SELECT v.Id,N'''+@Name+N' row ''+CONVERT(nvarchar(10),v.Id)'+@Values+
            N' FROM (VALUES(1),(2),(3)) v(Id);';
        EXEC sys.sp_executesql @Sql;
    END;
    FETCH NEXT FROM FillNodes INTO @Name,@IsRoot;
END;
CLOSE FillNodes;
DEALLOCATE FillNodes;

IF EXISTS (
    SELECT TableName FROM Archive.ArchiveJobs
    WHERE DatabaseName=@DatabaseName AND TableName LIKE N'ArchiveScenarioTest.%'
    GROUP BY TableName HAVING COUNT(*)>1
) THROW 50014,'Duplicate scenario jobs must be resolved before reseeding.',1;

-- Keep job identities stable across repeats and reset their processing state.
INSERT Archive.ArchiveJobs(DatabaseName,TableName,DateColumn,ArchiveOlderThanDays)
SELECT @DatabaseName,N'ArchiveScenarioTest.'+n.Name,N'CreatedAt',30
FROM @Nodes n WHERE n.IsRoot=1 AND NOT EXISTS (
    SELECT 1 FROM Archive.ArchiveJobs j
    WHERE j.DatabaseName=@DatabaseName AND j.TableName=N'ArchiveScenarioTest.'+n.Name
);
UPDATE j SET DateColumn=N'CreatedAt',ArchiveOlderThanDays=30,LastProcessedAt=NULL,
    LastSuccesProcessedAt=NULL,LastProcessedStatus=NULL,ErrorMessage=NULL
FROM Archive.ArchiveJobs j JOIN @Nodes n ON j.TableName=N'ArchiveScenarioTest.'+n.Name AND n.IsRoot=1
WHERE j.DatabaseName=@DatabaseName;

DELETE r FROM Archive.ArchiveJobRelations r JOIN Archive.ArchiveJobs j ON j.Id=r.ArchiveJobId
WHERE j.DatabaseName=@DatabaseName AND j.TableName LIKE N'ArchiveScenarioTest.%';
INSERT Archive.ArchiveJobRelations(ArchiveJobId,DatabaseName,ParentTable,ChildTable,ParentKeyColumn,ChildKeyColumn)
SELECT j.Id,@DatabaseName,N'ArchiveScenarioTest.'+e.ParentName,N'ArchiveScenarioTest.'+e.ChildName,N'Id',e.ChildColumn
FROM @Edges e JOIN Archive.ArchiveJobs j ON j.DatabaseName=@DatabaseName AND
    j.TableName=N'ArchiveScenarioTest.Root'+RIGHT(N'0'+CONVERT(nvarchar(2),e.RootNumber),2);
