# WealthSync database launcher (Windows PowerShell)
# Ensures the local PostgreSQL Windows service is running.
# Database/user creation is documented in backend/POSTGRESQL.md.
$ErrorActionPreference = "Stop"

$service = Get-Service -Name "postgresql*" -ErrorAction SilentlyContinue |
    Select-Object -First 1

if (-not $service) {
    Write-Error "No PostgreSQL Windows service found. Install PostgreSQL first (see backend/POSTGRESQL.md)."
    exit 1
}

if ($service.Status -ne "Running") {
    Write-Host "Starting service $($service.Name)..."
    Start-Service -Name $service.Name
}

$port = if ($env:POSTGRES_PORT) { [int]$env:POSTGRES_PORT } else { 5432 }
$listening = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue
if (-not $listening) {
    Write-Error "Service $($service.Name) is running but nothing is listening on port $port."
    exit 1
}

Write-Host "PostgreSQL is running on 127.0.0.1:$port ($($service.Name))."
