@echo off
REM Build and push Docker image to Quay.io (Windows version)
setlocal enabledelayedexpansion

echo ==========================================
echo News Service - Build ^& Push to Quay.io
echo ==========================================
echo.

REM Configuration file for Quay username
set CONFIG_FILE=.quay-config

REM Check if docker or podman is available
set CONTAINER_CLI=
where docker >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    set CONTAINER_CLI=docker
    echo + Using Docker
) else (
    where podman >nul 2>&1
    if %ERRORLEVEL% EQU 0 (
        set CONTAINER_CLI=podman
        echo + Using Podman
    ) else (
        echo X Error: Neither Docker nor Podman found
        echo Please install Docker or Podman
        exit /b 1
    )
)
echo.

REM Get Quay.io username
echo.
echo Quay.io Configuration
echo ---------------------
if exist "%CONFIG_FILE%" (
    set /p QUAY_USERNAME=<"%CONFIG_FILE%"
    echo Current username: !QUAY_USERNAME!
    set /p USE_EXISTING="Use this username? [Y/n]: "
    if /i "!USE_EXISTING!"=="n" (
        set /p QUAY_USERNAME="Enter Quay.io username: "
        echo !QUAY_USERNAME!>"%CONFIG_FILE%"
        echo + Username saved to %CONFIG_FILE%
    )
) else (
    set /p QUAY_USERNAME="Enter Quay.io username: "
    if "!QUAY_USERNAME!"=="" (
        echo X Error: Username cannot be empty
        exit /b 1
    )
    echo !QUAY_USERNAME!>"%CONFIG_FILE%"
    echo + Username saved to %CONFIG_FILE%
)
echo.

REM Get version tag
echo.
echo Image Version
echo -------------
set /p VERSION="Enter version tag [latest]: "
if "!VERSION!"=="" set VERSION=latest
echo.

REM Image names
set IMAGE_NAME=news-service
set FULL_IMAGE=quay.io/!QUAY_USERNAME!/!IMAGE_NAME!:!VERSION!

REM Build image
echo.
echo Step 1/4: Building Docker image...
echo ----------------------------------
echo Image: !FULL_IMAGE!
%CONTAINER_CLI% build -t "!IMAGE_NAME!:!VERSION!" -t "!IMAGE_NAME!:latest" .
if %ERRORLEVEL% NEQ 0 (
    echo X Build failed
    exit /b 1
)
echo + Image built successfully
echo.

REM Tag for Quay.io
echo Step 2/4: Tagging image for Quay.io...
echo ---------------------------------------
%CONTAINER_CLI% tag "!IMAGE_NAME!:!VERSION!" "!FULL_IMAGE!"
if not "!VERSION!"=="latest" (
    %CONTAINER_CLI% tag "!IMAGE_NAME!:!VERSION!" "quay.io/!QUAY_USERNAME!/!IMAGE_NAME!:latest"
)
echo + Image tagged
echo.

REM Check if logged in to Quay.io
echo Step 3/4: Checking Quay.io login...
echo -----------------------------------
%CONTAINER_CLI% login quay.io --get-login >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo ! Not logged in to Quay.io
    echo Attempting to login...
    %CONTAINER_CLI% login quay.io
    if %ERRORLEVEL% NEQ 0 (
        echo X Login failed
        exit /b 1
    )
) else (
    for /f "delims=" %%i in ('%CONTAINER_CLI% login quay.io --get-login') do set LOGGED_IN_USER=%%i
    echo + Already logged in as: !LOGGED_IN_USER!
)
echo.

REM Push image
echo Step 4/4: Pushing image to Quay.io...
echo -------------------------------------
%CONTAINER_CLI% push "!FULL_IMAGE!"
if %ERRORLEVEL% NEQ 0 (
    echo X Push failed
    exit /b 1
)
if not "!VERSION!"=="latest" (
    echo Also pushing as latest...
    %CONTAINER_CLI% push "quay.io/!QUAY_USERNAME!/!IMAGE_NAME!:latest"
)
echo + Image pushed successfully
echo.

REM Ask to update deployment.yaml
echo Update deployment configuration?
echo --------------------------------
set DEPLOYMENT_FILE=openshift\deployment.yaml
if exist "%DEPLOYMENT_FILE%" (
    for /f "tokens=2" %%i in ('findstr /c:"image:" "%DEPLOYMENT_FILE%"') do set CURRENT_IMAGE=%%i
    echo Current image in deployment.yaml: !CURRENT_IMAGE!
    echo New image: !FULL_IMAGE!
    set /p UPDATE_DEPLOYMENT="Update deployment.yaml with new image? [Y/n]: "
    if /i "!UPDATE_DEPLOYMENT!"=="" set UPDATE_DEPLOYMENT=Y

    if /i "!UPDATE_DEPLOYMENT!"=="Y" (
        REM Backup original
        copy "%DEPLOYMENT_FILE%" "%DEPLOYMENT_FILE%.bak" >nul

        REM Update image line using PowerShell
        powershell -Command "(Get-Content '%DEPLOYMENT_FILE%') -replace 'image:.*', 'image: !FULL_IMAGE!' | Set-Content '%DEPLOYMENT_FILE%'"

        echo + Updated %DEPLOYMENT_FILE%
        echo   Backup saved to %DEPLOYMENT_FILE%.bak
    )
)
echo.

REM Summary
echo ==========================================
echo Build ^& Push Complete!
echo ==========================================
echo.
echo Image Information:
echo   Registry: quay.io
echo   Repository: !QUAY_USERNAME!/!IMAGE_NAME!
echo   Tag: !VERSION!
echo   Full: !FULL_IMAGE!
echo.
echo Image URLs:
echo   https://quay.io/repository/!QUAY_USERNAME!/!IMAGE_NAME!
echo.
echo Next Steps:
if /i "!UPDATE_DEPLOYMENT!"=="Y" (
    echo   1. Review changes in %DEPLOYMENT_FILE%
    echo   2. Deploy to OpenShift:
    echo      deploy.bat
) else (
    echo   1. Update %DEPLOYMENT_FILE% with the new image
    echo   2. Deploy to OpenShift:
    echo      deploy.bat
)
echo.
echo   Or update running deployment directly:
echo   oc set image deployment/news-service news-service=!FULL_IMAGE!
echo.
echo Build successful!

endlocal
