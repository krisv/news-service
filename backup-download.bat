@echo off
REM Download PostgreSQL backup from OpenShift to local machine

echo + Downloading database backup from OpenShift...
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

REM Create backup directory locally if it doesn't exist
if not exist "backups" mkdir backups

REM Generate backup filename with timestamp
for /f "tokens=2 delims==" %%i in ('wmic os get localdatetime /value') do set datetime=%%i
set TIMESTAMP=%datetime:~0,8%-%datetime:~8,6%
set BACKUP_FILE=backups\news-backup-%TIMESTAMP%.sql.gz

echo + Creating backup on server...
oc exec %POSTGRES_POD% -- bash -c "pg_dump -U krisv news | gzip > /tmp/backup.sql.gz"

if errorlevel 1 (
    echo X Error: Failed to create backup
    exit /b 1
)

echo + Downloading backup to local machine...
oc cp %POSTGRES_POD%:/tmp/backup.sql.gz %BACKUP_FILE%

if errorlevel 1 (
    echo X Error: Failed to download backup
    exit /b 1
)

echo + Cleaning up temporary file...
oc exec %POSTGRES_POD% -- rm /tmp/backup.sql.gz

echo.
echo + Backup completed successfully!
echo   File: %BACKUP_FILE%
dir %BACKUP_FILE%
echo.
echo   To restore this backup, run: backup-restore.bat %BACKUP_FILE%
