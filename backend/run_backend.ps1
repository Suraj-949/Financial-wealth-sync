# WealthSync backend launcher (Windows PowerShell)
# Starts the FastAPI service on http://127.0.0.1:8000 and opens the dashboard.
$ErrorActionPreference = "Stop"
$py = "C:\Users\SURAJ\anaconda3\python.exe"
Start-Process powershell -ArgumentList "-NoExit", "-Command", "& '$py' -m uvicorn backend.main:app --host 0.0.0.0 --port 8000"
Start-Sleep -Seconds 3
Start-Process "http://127.0.0.1:8000/docs"
Write-Host "WealthSync API docs: http://127.0.0.1:8000/docs  (press Ctrl+C in the uvicorn window to stop)"