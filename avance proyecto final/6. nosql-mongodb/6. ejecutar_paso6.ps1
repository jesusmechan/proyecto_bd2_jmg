# PASO 6 — MongoDB (delivery_nosql)
# Ejecutar desde PowerShell:
#   cd "avance proyecto final\6. nosql-mongodb"
#   .\6. ejecutar_paso6.ps1
#
# Requisitos: MongoDB en ejecución + mongosh en el PATH
# (no depende de PostgreSQL; los .js generan datos de ejemplo en NoSQL)

$ErrorActionPreference = "Stop"
$here = $PSScriptRoot

function Invoke-MongoshFile {
    param(
        [string]$File,
        [string]$Database = ""
    )
    if (-not (Test-Path $File)) {
        throw "No se encuentra: $File"
    }
    Write-Host "`n>> $([IO.Path]::GetFileName($File))" -ForegroundColor Cyan
    if ($Database) {
        & mongosh $Database --file $File
    } else {
        & mongosh --file $File
    }
    if ($LASTEXITCODE -ne 0) {
        throw "mongosh falló en $File (código $LASTEXITCODE)"
    }
}

if (-not (Get-Command mongosh -ErrorAction SilentlyContinue)) {
    Write-Host "mongosh no está en el PATH." -ForegroundColor Red
    Write-Host "Instala MongoDB Community Server (incluye mongosh) o MongoDB Shell:"
    Write-Host "  https://www.mongodb.com/try/download/community"
    Write-Host "Luego reinicia la terminal y vuelve a ejecutar este script."
    exit 1
}

Write-Host "=== PASO 6 — MongoDB delivery_nosql ===" -ForegroundColor Green

Invoke-MongoshFile -File (Join-Path $here "1. casos_20_migracion.js")
Invoke-MongoshFile -File (Join-Path $here "2. indices.js") -Database "delivery_nosql"
Invoke-MongoshFile -File (Join-Path $here "3. agregaciones.js") -Database "delivery_nosql"
Invoke-MongoshFile -File (Join-Path $here "4. validaciones.js") -Database "delivery_nosql"

Write-Host "`n=== Listo. Verificar en mongosh ===" -ForegroundColor Green
Write-Host @"
mongosh delivery_nosql
show collections
db.pedidos_docs.countDocuments()
db.pedidos_docs.findOne({ region_codigo: "LIM-N" })
"@
