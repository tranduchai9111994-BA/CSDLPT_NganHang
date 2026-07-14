@echo off
echo ========================================================
echo  KHOI DONG HE THONG APP NGAN HANG
echo ========================================================

REM Kill process dang chay tren port 3001 (neu co)
for /f "tokens=5" %%a in ('netstat -aon ^| findstr ":3001.*LISTENING"') do (
    echo Dang tat process cu PID=%%a tren port 3001...
    taskkill /F /PID %%a >nul 2>&1
)

cd /d "%~dp0APP_NGANHANG"
start http://localhost:3001
npm start
pause
