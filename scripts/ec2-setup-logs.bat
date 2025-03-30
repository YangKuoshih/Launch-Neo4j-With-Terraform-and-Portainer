@REM This batch file connects to the EC2 instance to tail its logs.
@echo off
setlocal enabledelayedexpansion

echo Waiting for the log to start...

set REMOTE_FILE=/home/ec2-user/.local/bin/tail_setup_log

:check_log
:: Use SSH with your private key to check if the helper log script exists on the EC2 instance.
ssh -i "%PROJECT_DIR%\keys\private_key.pem" ec2-user@%ELASTIC_IP% "test -f %REMOTE_FILE% && exit 0 || exit 1"
if %errorlevel% equ 0 (
    echo Log is ready. Starting tail...
    ssh -i "%PROJECT_DIR%\keys\private_key.pem" ec2-user@%ELASTIC_IP% "tail_setup_log"
) else (
    echo Waiting for log to become available...
    timeout /t 5 /nobreak >nul
    goto check_log
)

endlocal
