-- run on master database
ALTER DATABASE [primarydatabasename]
ADD SECONDASRY SERVER [replicaervername]
WITH (SECONDARY_TYPE=Named, DATABASE_NAME=[namereplicadatabasename])
GO
