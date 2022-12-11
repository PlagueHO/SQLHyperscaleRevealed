SELECT file_id
, name AS file_name
, type_desc
, size * 8 / 1024 / 1024 AS file_size_GB
, max_size * 8 / 1024 / 1024 AS max_file_size_GB
, growth * 8 / 1024 / 1024 AS growth_size_GB
FROM sys.database_files WHERE type_desc IN ('ROWS', 'LOG')
