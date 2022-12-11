SELECT database_id as 'DB ID'
, slo_name as 'Service Level Objective'
, server_name as 'Server Name'
, cpu_limit as 'CPU Limit'
, database_name as 'DB Name'
, primary_max_log_rate/1024/1024 as 'Log Throughtput MB/s'
, max_db_max_size_in_mb/1024/1024 as 'MAX DB Size in TB'
, max_db_max_size_in_mb as 'MAX DB Size in MB'
FROM sys.dm_user_db_resource_governance
