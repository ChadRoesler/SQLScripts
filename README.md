# SQLScripts
A Rag Tag bunch of SQL scripts

In 2012, a crack procedure unit was sent to a repository by a company for a git they didn't commit. These procedures promptly escaped from a maximum security database to the Minnesota underground. Today, still wanted by the company they survive as stored procedures of fortune. If you have a problem, if no one else can help, and if you can find them....maybe you can use them.


Util_BackupTableDiff: Used for diffing two tables. You can check for deleted, inserted or updated rows.  Will also return the printed statements for restoring the data, along with listing any constrainted tables that you may want to check as well.

Util_Devops_ObjDiff: Used for diffing procedures based on a checksum stored in an Admin table.  This can also be used to generate the Checksums as well for a release db.

Util_dropper: Drop all temp tables associated to a SPID.

Util_Dynamomatic: Generates Dynamic SQL for you.

Util_TriggerMan: Generates a trigger that can self destruct, for auditing a table.

Util_WHOUSESSPRENAME_SERIOUSLY: Sometimes people use SP_Rename, find out what procedures have been impacted by this, and correct it.
