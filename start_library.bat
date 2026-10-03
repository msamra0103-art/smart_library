@echo off
chcp 65001 >nul
title Manara Smart Library - LAN Server
where node >nul 2>nul
if errorlevel 1 (
  echo Node.js غير مثبت على الجهاز.
  echo يمكنك فتح index.html للوضع المحلي، أو تثبيت Node.js لتشغيل عدة أجهزة على الشبكة.
  pause
  exit /b 1
)
node server.js
pause
