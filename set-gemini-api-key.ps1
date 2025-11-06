# Script pour configurer la clé API Gemini
# Usage: .\set-gemini-api-key.ps1 -ApiKey "VOTRE_CLE_API_ICI"

param(
    [Parameter(Mandatory=$true)]
    [string]$ApiKey
)

Write-Host "🔑 Configuration de la clé API Gemini..." -ForegroundColor Cyan

# Définir la variable d'environnement pour la session actuelle
$env:GEMINI_API_KEY = $ApiKey
Write-Host "✅ Variable d'environnement GEMINI_API_KEY définie pour cette session PowerShell" -ForegroundColor Green

# Option : Définir la variable d'environnement de façon persistante (au niveau utilisateur)
Write-Host ""
Write-Host "Voulez-vous sauvegarder cette clé de façon permanente pour votre compte utilisateur ? (O/N)" -ForegroundColor Yellow
$response = Read-Host

if ($response -eq "O" -or $response -eq "o") {
    [System.Environment]::SetEnvironmentVariable("GEMINI_API_KEY", $ApiKey, [System.EnvironmentVariableTarget]::User)
    Write-Host "✅ Variable d'environnement sauvegardée de façon permanente" -ForegroundColor Green
    Write-Host "⚠️  Redémarrez VS Code pour que les nouveaux terminaux utilisent cette variable" -ForegroundColor Yellow
} else {
    Write-Host "ℹ️  La clé sera disponible uniquement dans cette session PowerShell" -ForegroundColor Cyan
}

Write-Host ""
Write-Host "📝 Pour obtenir votre clé API Gemini :" -ForegroundColor Cyan
Write-Host "   1. Allez sur https://makersuite.google.com/app/apikey" -ForegroundColor White
Write-Host "   2. Cliquez sur 'Create API Key'" -ForegroundColor White
Write-Host "   3. Copiez la clé et lancez :" -ForegroundColor White
Write-Host "      .\set-gemini-api-key.ps1 -ApiKey `"VOTRE_CLE`"" -ForegroundColor Yellow
Write-Host ""
Write-Host "🚀 Vous pouvez maintenant lancer l'application avec : dotnet run" -ForegroundColor Green
