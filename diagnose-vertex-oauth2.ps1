# 🚀 DIAGNOSTIC ET CORRECTION VERTEX AI OAUTH2 - TECHNOLOGIE DE POINTE
Write-Host "🔧 DIAGNOSTIC VERTEX AI OAUTH2 - SÉCURITÉ MAXIMALE" -ForegroundColor Cyan
Write-Host "════════════════════════════════════════════════════════════" -ForegroundColor Cyan

$projectId = "prototypevmed237"
$serviceAccount = "prototypevmed237@prototypevmed237.iam.gserviceaccount.com"

Write-Host "📋 Configuration actuelle:"
Write-Host "   • Projet: $projectId" -ForegroundColor Yellow
Write-Host "   • Service Account: $serviceAccount" -ForegroundColor Yellow
Write-Host "   • Région: us-central1 (PREMIUM)" -ForegroundColor Yellow
Write-Host ""

Write-Host "🔍 DIAGNOSTIC DES PERMISSIONS REQUISES:" -ForegroundColor Green
$requiredRoles = @(
    "roles/aiplatform.user",
    "roles/ml.developer", 
    "roles/serviceusage.serviceUsageConsumer",
    "roles/compute.viewer"
)

Write-Host "📝 Rôles IAM requis pour Vertex AI:" -ForegroundColor Magenta
foreach ($role in $requiredRoles) {
    Write-Host "   🔐 $role" -ForegroundColor Blue
}

Write-Host ""
Write-Host "🎯 COMMANDES GCLOUD POUR CORRIGER LES PERMISSIONS:" -ForegroundColor Green
Write-Host "# 1. Activer les APIs Vertex AI" -ForegroundColor Yellow
Write-Host "gcloud services enable aiplatform.googleapis.com --project=$projectId" -ForegroundColor White
Write-Host "gcloud services enable ml.googleapis.com --project=$projectId" -ForegroundColor White
Write-Host ""

Write-Host "# 2. Ajouter les permissions IAM au Service Account" -ForegroundColor Yellow
foreach ($role in $requiredRoles) {
    Write-Host "gcloud projects add-iam-policy-binding $projectId --member=`"serviceAccount:$serviceAccount`" --role=`"$role`"" -ForegroundColor White
}

Write-Host ""
Write-Host "🏆 SOLUTION ALTERNATIVE - TOKEN TEMPORAIRE:" -ForegroundColor Green
Write-Host "Si vous n'avez pas gcloud CLI, utilisez une API KEY temporaire:" -ForegroundColor Yellow
Write-Host "1. Aller sur https://console.cloud.google.com/apis/credentials" -ForegroundColor White
Write-Host "2. Créer une API Key" -ForegroundColor White
Write-Host "3. Restreindre à 'Vertex AI API'" -ForegroundColor White
Write-Host "4. Définir GEMINI_API_KEY dans l'environnement" -ForegroundColor White

Write-Host ""
Write-Host "✅ VERTEX AI OAUTH2 - PRÊT POUR LA CORRECTION!" -ForegroundColor Green
Write-Host "════════════════════════════════════════════════════════════" -ForegroundColor Cyan