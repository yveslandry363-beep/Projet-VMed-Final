# Configuration Vertex AI pour prototypevmed237
# Script simplifie sans caracteres speciaux

Write-Host "Configuration de Vertex AI" -ForegroundColor Cyan
Write-Host ""

# Etape 1: Activer l'API
Write-Host "ETAPE 1: Activer l'API Vertex AI" -ForegroundColor Yellow
$apiUrl = "https://console.cloud.google.com/apis/library/aiplatform.googleapis.com?project=prototypevmed237"
Start-Process $apiUrl
Write-Host "  -> Cliquez sur ACTIVER dans la page" -ForegroundColor White
Write-Host ""
Write-Host "Appuyez sur ENTREE une fois l'API activee..." -ForegroundColor Cyan
Read-Host

# Etape 2: Permissions IAM
Write-Host ""
Write-Host "ETAPE 2: Donner les permissions" -ForegroundColor Yellow
$iamUrl = "https://console.cloud.google.com/iam-admin/iam?project=prototypevmed237"
Start-Process $iamUrl
Write-Host "  -> Cherchez: prototypevmed237@prototypevmed237.iam.gserviceaccount.com" -ForegroundColor White
Write-Host "  -> Cliquez sur le crayon (editer)" -ForegroundColor White
Write-Host "  -> AJOUTER UN AUTRE ROLE" -ForegroundColor White
Write-Host "  -> Selectionnez: Vertex AI User" -ForegroundColor White
Write-Host "  -> Cliquez sur ENREGISTRER" -ForegroundColor White
Write-Host ""
Write-Host "Appuyez sur ENTREE une fois termine..." -ForegroundColor Cyan
Read-Host

# Etape 3: Verification
Write-Host ""
Write-Host "ETAPE 3: Verification de gcp-key.json" -ForegroundColor Yellow
if (Test-Path ".\gcp-key.json") {
    $gcpKey = Get-Content ".\gcp-key.json" | ConvertFrom-Json
    Write-Host "  Service Account: $($gcpKey.client_email)" -ForegroundColor Green
    Write-Host "  Project ID: $($gcpKey.project_id)" -ForegroundColor Green
    Write-Host "  FICHIER VALIDE!" -ForegroundColor Green
} else {
    Write-Host "  ERREUR: gcp-key.json non trouve!" -ForegroundColor Red
    exit 1
}

# Resume
Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "CONFIGURATION TERMINEE!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "Vous pouvez maintenant lancer:" -ForegroundColor Cyan
Write-Host "  dotnet run" -ForegroundColor White
Write-Host ""
Write-Host "Logs attendus:" -ForegroundColor Cyan
Write-Host "  [GEMINI_AUTH] Utilisation de OAuth2..." -ForegroundColor Gray
Write-Host "  [VICTORY_API] Reponse de gemini-flash recue" -ForegroundColor Gray
Write-Host ""
