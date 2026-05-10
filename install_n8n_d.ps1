# Script para instalar n8n en el Disco D y configurar la carpeta de datos
Write-Host "Iniciando instalación de n8n en D:\n8n_servidor..." -ForegroundColor Cyan

# Crear carpeta si no existe
if (!(Test-Path "D:\n8n_servidor")) {
    New-Item -ItemType Directory -Path "D:\n8n_servidor"
}

# Establecer variable de entorno para la sesión actual
$env:N8N_USER_FOLDER = "D:\n8n_servidor"

# Entrar a la carpeta e instalar
Set-Location "D:\n8n_servidor"
npm install n8n

# Crear un lanzador fácil en el escritorio o en la carpeta
$launcherContent = @"
@echo off
set N8N_USER_FOLDER=D:\n8n_servidor
cd /d D:\n8n_servidor
npx n8n
"@
$launcherContent | Out-File -FilePath "D:\n8n_servidor\iniciar_n8n.bat" -Encoding ASCII

Write-Host "¡Listo! Ahora puedes iniciar n8n ejecutando D:\n8n_servidor\iniciar_n8n.bat" -ForegroundColor Green
