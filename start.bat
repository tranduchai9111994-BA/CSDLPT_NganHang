@echo off
echo ========================================================
echo  KHOI DONG HE THONG APP NGAN HANG
echo ========================================================
cd /d "%~dp0APP_NGANHANG"
start http://localhost:3001
npm start
pause
