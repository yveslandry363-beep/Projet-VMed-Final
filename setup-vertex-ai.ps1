# Script pour configurer Vertex AI dans Google Cloud
# Projet: prototypevmed237

Write-Host "🚀 Configuration de Vertex AI pour le projet prototypevmed237" -ForegroundColor Cyan
Write-Host ""

# Étape 1: Ouvrir la console pour activer l'API
Write-Host "📋 ÉTAPE 1: Activer l'API Vertex AI" -ForegroundColor Yellow
Write-Host "   Je vais ouvrir la page Google Cloud Console..." -ForegroundColor White
Write-Host ""
Start-Sleep -Seconds 2

$apiUrl = "https://console.cloud.google.com/apis/library/aiplatform.googleapis.com?project=prototypevmed237"
Start-Process $apiUrl

Write-Host "   ✅ Dans la page qui s'ouvre:" -ForegroundColor Green
Write-Host "      1. Cliquez sur le bouton bleu 'ACTIVER'" -ForegroundColor White
Write-Host "      2. Attendez quelques secondes (activation automatique)" -ForegroundColor White
Write-Host ""
Write-Host "   Appuyez sur ENTRÉE une fois l'API activée..." -ForegroundColor Yellow
Read-Host

# Étape 2: Vérifier les permissions du Service Account
Write-Host ""
Write-Host "📋 ÉTAPE 2: Donner les permissions au Service Account" -ForegroundColor Yellow
Write-Host "   Je vais ouvrir la page IAM..." -ForegroundColor White
Write-Host ""
Start-Sleep -Seconds 2

$iamUrl = "https://console.cloud.google.com/iam-admin/iam?project=prototypevmed237"
Start-Process $iamUrl

Write-Host "   ✅ Dans la page IAM qui s'ouvre:" -ForegroundColor Green
Write-Host "      1. Cherchez: prototypevmed237@prototypevmed237.iam.gserviceaccount.com" -ForegroundColor White
Write-Host "      2. Cliquez sur le crayon (✏️) pour éditer" -ForegroundColor White
Write-Host "      3. Cliquez sur 'AJOUTER UN AUTRE RÔLE'" -ForegroundColor White
Write-Host "      4. Cherchez et sélectionnez: 'Vertex AI User'" -ForegroundColor White
Write-Host "      5. Cliquez sur 'ENREGISTRER'" -ForegroundColor White
Write-Host ""
Write-Host "   Appuyez sur ENTRÉE une fois les permissions accordées..." -ForegroundColor Yellow
Read-Host

# Étape 3: Vérifier que gcp-key.json existe
Write-Host ""
Write-Host "📋 ÉTAPE 3: Vérification de gcp-key.json" -ForegroundColor Yellow

$gcpKeyPath = ".\gcp-key.json"
if (Test-Path $gcpKeyPath) {
    Write-Host "   ✅ Fichier gcp-key.json trouvé!" -ForegroundColor Green
    
    # Lire le contenu pour vérifier
    $gcpKey = Get-Content $gcpKeyPath | ConvertFrom-Json
    Write-Host "   📧 Service Account: $($gcpKey.client_email)" -ForegroundColor Cyan
    Write-Host "   🆔 Project ID: $($gcpKey.project_id)" -ForegroundColor Cyan
} else {
    Write-Host "   ❌ Fichier gcp-key.json NON trouvé!" -ForegroundColor Red
    Write-Host "   📍 Emplacement attendu: $((Get-Location).Path)\gcp-key.json" -ForegroundColor Yellow
    exit 1
}

# Étape 4: Test de l'authentification
Write-Host ""
Write-Host "📋 ÉTAPE 4: Test de l'authentification (optionnel)" -ForegroundColor Yellow
Write-Host "   Voulez-vous tester l'authentification OAuth2 maintenant? (O/N)" -ForegroundColor Cyan
$response = Read-Host

if ($response -eq "O" -or $response -eq "o") {
    Write-Host "   🔄 Installation de gcloud CLI nécessaire..." -ForegroundColor Yellow
    Write-Host "   📥 Téléchargez: https://cloud.google.com/sdk/docs/install" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "   Puis exécutez:" -ForegroundColor White
    Write-Host "   gcloud auth activate-service-account --key-file=gcp-key.json" -ForegroundColor Gray
    Write-Host "   gcloud config set project prototypevmed237" -ForegroundColor Gray
    Write-Host "   gcloud services list --enabled | Select-String 'aiplatform'" -ForegroundColor Gray
}

# Résumé final
Write-Host ""
Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Green
Write-Host "✅ CONFIGURATION TERMINÉE!" -ForegroundColor Green
Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Green
Write-Host ""
Write-Host "🚀 Vous pouvez maintenant lancer l'application:" -ForegroundColor Cyan
Write-Host "   dotnet run" -ForegroundColor White
Write-Host ""
Write-Host "📊 L'application utilisera:" -ForegroundColor Cyan
Write-Host "   ✅ OAuth2 avec Service Account (gcp-key.json)" -ForegroundColor Green
Write-Host "   ✅ Vertex AI API endpoint" -ForegroundColor Green
Write-Host "   ✅ Modèle: gemini-flash (Vertex AI)" -ForegroundColor Green
Write-Host "   ✅ Région: europe-west4" -ForegroundColor Green
Write-Host ""
Write-Host "📝 Logs à surveiller:" -ForegroundColor Cyan
Write-Host "   [GEMINI_AUTH] Utilisation de OAuth2 avec Service Account" -ForegroundColor Gray
Write-Host "   [VICTORY_API] Réponse de gemini-flash reçue" -ForegroundColor Gray
Write-Host ""
Write-Host "🔍 En cas d'erreur, vérifiez:" -ForegroundColor Yellow
Write-Host "   1. L'API Vertex AI est activee" -ForegroundColor White
Write-Host "   2. Le Service Account a le role 'Vertex AI User'" -ForegroundColor White
Write-Host "   3. Le fichier gcp-key.json est present" -ForegroundColor White
Write-Host ""
