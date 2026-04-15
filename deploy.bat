@echo off
REM OpenShift Deployment Script for News Service (Windows version)
setlocal enabledelayedexpansion

echo ==========================================
echo News Service - OpenShift Deployment
echo ==========================================
echo.

REM API key file
set API_KEY_FILE=.api-key

REM Check if oc is installed
where oc >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo X Error: oc (OpenShift CLI^) is not installed
    echo Install from: https://docs.openshift.com/container-platform/latest/cli_reference/openshift_cli/getting-started-cli.html
    exit /b 1
)

REM Check if logged in
echo Checking OpenShift login status...
oc whoami >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo X Error: Not logged in to OpenShift
    echo Please login first with: oc login ^<cluster-url^>
    exit /b 1
)

for /f "delims=" %%i in ('oc whoami') do set CURRENT_USER=%%i
for /f "delims=" %%i in ('oc whoami --show-server') do set CURRENT_SERVER=%%i
echo + Logged in as: !CURRENT_USER!
echo + Server: !CURRENT_SERVER!
echo.

REM Check current project
for /f "delims=" %%i in ('oc project -q 2^>nul') do set CURRENT_PROJECT=%%i
if "!CURRENT_PROJECT!"=="" (
    echo ! No project selected
    set /p PROJECT_NAME="Enter project name to create/use [news-service]: "
    if "!PROJECT_NAME!"=="" set PROJECT_NAME=news-service

    oc project "!PROJECT_NAME!" >nul 2>&1
    if %ERRORLEVEL% EQU 0 (
        echo + Switched to existing project: !PROJECT_NAME!
    ) else (
        echo Creating new project: !PROJECT_NAME!
        oc new-project "!PROJECT_NAME!"
        echo + Created and switched to project: !PROJECT_NAME!
    )
) else (
    echo Current project: !CURRENT_PROJECT!
    set /p CONFIRM="Deploy to this project? [Y/n]: "
    if /i not "!CONFIRM!"=="Y" if /i not "!CONFIRM!"=="" (
        set /p PROJECT_NAME="Enter project name to create/use: "
        oc project "!PROJECT_NAME!" >nul 2>&1
        if %ERRORLEVEL% EQU 0 (
            echo + Switched to existing project: !PROJECT_NAME!
        ) else (
            echo Creating new project: !PROJECT_NAME!
            oc new-project "!PROJECT_NAME!"
            echo + Created and switched to project: !PROJECT_NAME!
        )
    )
)
echo.

REM Generate or load API key
echo Configuring API key...
if exist "%API_KEY_FILE%" (
    set /p API_KEY=<"%API_KEY_FILE%"
    echo + Using existing API key from %API_KEY_FILE%
) else (
    REM Generate API key using PowerShell
    for /f "delims=" %%i in ('powershell -Command "Add-Type -AssemblyName System.Web; [System.Web.Security.Membership]::GeneratePassword(43, 10)"') do set API_KEY=%%i
    echo !API_KEY!>"%API_KEY_FILE%"
    echo + Generated new API key and saved to %API_KEY_FILE%
)
echo.

REM Deploy PostgreSQL
echo Step 1/7: Deploying PostgreSQL...
echo ----------------------------------
oc apply -f openshift\postgres-deployment.yaml
if %ERRORLEVEL% NEQ 0 (
    echo X Failed to deploy PostgreSQL
    exit /b 1
)
echo + PostgreSQL deployment created
echo.

REM Wait for PostgreSQL to be ready
echo Waiting for PostgreSQL to be ready...
oc wait --for=condition=available --timeout=120s deployment/postgres
if %ERRORLEVEL% NEQ 0 (
    echo ! PostgreSQL deployment timeout, checking status...
    oc get pods -l app=news-service-db
)
echo + PostgreSQL is ready
echo.

REM Initialize database
echo Step 2/7: Initializing database schema...
echo ------------------------------------------
REM Delete old job if exists
oc delete job news-service-init-db --ignore-not-found=true >nul 2>&1
oc apply -f openshift\init-db-job.yaml
if %ERRORLEVEL% NEQ 0 (
    echo X Failed to create init job
    exit /b 1
)
echo Waiting for database initialization...
oc wait --for=condition=complete --timeout=60s job/news-service-init-db
if %ERRORLEVEL% NEQ 0 (
    echo ! Checking job logs...
    oc logs job/news-service-init-db
)
echo + Database initialized
echo.

REM Create ConfigMap
echo Step 3/7: Creating ConfigMap...
echo --------------------------------
oc apply -f openshift\configmap.yaml
if %ERRORLEVEL% NEQ 0 (
    echo X Failed to create ConfigMap
    exit /b 1
)
echo + ConfigMap created
echo.

REM Update API key in secret
echo Step 4/7: Updating API key in secret...
echo ----------------------------------------
oc patch secret news-service-secrets -p "{\"stringData\":{\"API_KEY\":\"!API_KEY!\"}}" --type=merge
if %ERRORLEVEL% NEQ 0 (
    echo X Failed to update API key
    exit /b 1
)
echo + API key configured
echo.

REM Deploy news service
echo Step 5/7: Deploying news service application...
echo ------------------------------------------------
oc apply -f openshift\deployment.yaml
oc apply -f openshift\service.yaml
oc apply -f openshift\route.yaml
if %ERRORLEVEL% NEQ 0 (
    echo X Failed to deploy news service
    exit /b 1
)
echo + News service deployed
echo.

REM Wait for deployment
echo Waiting for news service to be ready...
oc wait --for=condition=available --timeout=120s deployment/news-service
if %ERRORLEVEL% NEQ 0 (
    echo ! Deployment timeout, checking status...
    oc get pods -l app=news-service
)
echo + News service is ready
echo.

REM Setup backups
echo Step 6/7: Setting up automated backups...
echo -----------------------------------------
oc apply -f openshift\backup-cronjob.yaml
if %ERRORLEVEL% NEQ 0 (
    echo X Failed to setup backups
    exit /b 1
)
echo + Backup CronJob created (runs daily at 2 AM^)
echo.

REM Get route URL
echo Step 7/7: Getting service URL...
echo --------------------------------
for /f "delims=" %%i in ('oc get route news-service -o jsonpath^="{.spec.host}" 2^>nul') do set ROUTE_URL=%%i
if not "!ROUTE_URL!"=="" (
    set SERVICE_URL=https://!ROUTE_URL!
    echo + Route created
) else (
    echo ! Could not get route URL
    set SERVICE_URL=^<checking...^>
)
echo.

REM Summary
echo ==========================================
echo Deployment Complete!
echo ==========================================
echo.
echo Service Information:
echo   URL: !SERVICE_URL!
echo   API Key: !API_KEY!
echo   API Key File: %API_KEY_FILE%
echo.
echo Database Information:
echo   Host: postgres (internal service^)
echo   Database: news
echo   Username: krisv
echo   Password: krisv
echo.
echo Useful Commands:
echo   # View pods
echo   oc get pods
echo.
echo   # View logs
echo   oc logs -f deployment/news-service
echo.
echo   # Scale application
echo   oc scale deployment/news-service --replicas=3
echo.
echo   # Manual backup
echo   oc create job --from=cronjob/postgres-backup manual-backup
echo.
echo   # Test API (without auth^)
echo   curl !SERVICE_URL!/health
echo.
echo   # Test API (with auth^)
echo   curl -X POST !SERVICE_URL!/api/news ^
echo     -H "Content-Type: application/json" ^
echo     -H "X-API-Key: !API_KEY!" ^
echo     -d "{\"title\":\"Test\",\"content\":\"Hello\",\"labels\":[\"topic:AI\"]}"
echo.
echo Deployment successful!

endlocal
