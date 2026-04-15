@echo off
REM Restore PostgreSQL backup from local machine to OpenShift

if "%1"=="" (
    echo Usage: backup-restore.bat ^<backup-file^>
    echo.
    echo Example: backup-restore.bat backups\news-backup-20260415-143022.sql.gz
    echo.
    echo Available backups:
    if exist "backups\*.sql.gz" (
        dir /b backups\*.sql.gz
    ) else (
        echo   No backups found in backups\ directory
    )
    exit /b 1
)

set BACKUP_FILE=%1

if not exist "%BACKUP_FILE%" (
    echo X Error: Backup file not found: %BACKUP_FILE%
    exit /b 1
)

echo + Restoring database backup to OpenShift...
echo   Backup file: %BACKUP_FILE%
echo.

REM Get the PostgreSQL pod name
echo + Finding PostgreSQL pod...
for /f "tokens=*" %%i in ('oc get pods -l app=news-service-db -o jsonpath="{.items[0].metadata.name}"') do set POSTGRES_POD=%%i

if "%POSTGRES_POD%"=="" (
    echo X Error: Could not find PostgreSQL pod
    echo   Make sure the pod is running: oc get pods
    exit /b 1
)

echo   Found pod: %POSTGRES_POD%
echo.

REM Confirm with user
echo ! WARNING: This will DELETE all existing data and replace it with the backup!
set /p CONFIRM=Are you sure you want to continue? (yes/no):

if not "%CONFIRM%"=="yes" (
    echo   Restore cancelled.
    exit /b 0
)

echo.
echo + Uploading backup to server...
oc cp "%BACKUP_FILE%" %POSTGRES_POD%:/tmp/restore.sql.gz

if errorlevel 1 (
    echo X Error: Failed to upload backup
    exit /b 1
)

echo + Terminating active database connections...
oc exec %POSTGRES_POD% -- psql -U krisv postgres -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = 'news' AND pid <> pg_backend_pid();"

echo + Dropping existing database...
oc exec %POSTGRES_POD% -- dropdb -U krisv --if-exists news

echo + Creating fresh database...
oc exec %POSTGRES_POD% -- createdb -U krisv news

echo + Restoring backup...
oc exec %POSTGRES_POD% -- bash -c "gunzip < /tmp/restore.sql.gz | psql -U krisv news"

if errorlevel 1 (
    echo X Error: Failed to restore backup
    exit /b 1
)

echo + Cleaning up temporary file...
oc exec %POSTGRES_POD% -- rm /tmp/restore.sql.gz

echo.
echo + Restore completed successfully!
echo   Database has been restored from: %BACKUP_FILE%
echo.
echo   You may want to restart the news-service pod to refresh connections:
echo   oc delete pod -l app=news-service
