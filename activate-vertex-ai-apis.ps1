# ========================================
# 🚀 ACTIVATION VERTEX AI - TECHNOLOGIE DE POINTE
# ========================================

Write-Host ""
Write-Host "🚀 VERTEX AI - TECHNOLOGIE DE POINTE" -ForegroundColor Green
Write-Host "====================================" -ForegroundColor Green
Write-Host ""

$projectId = "prototypevmed237"
$region = "us-central1"

Write-Host "📋 Configuration:" -ForegroundColor Cyan
Write-Host "   Projet: $projectId" -ForegroundColor White
Write-Host "   Région: $region" -ForegroundColor White
Write-Host ""

# Vérifier si gcloud est installé
Write-Host "🔍 Vérification de gcloud CLI..." -ForegroundColor Yellow
try {
    $gcloudVersion = gcloud version --format="value(Google Cloud SDK)" 2>$null
    if ($gcloudVersion) {
        Write-Host "   ✅ gcloud CLI trouvé: $gcloudVersion" -ForegroundColor Green
    } else {
        Write-Host "   ❌ gcloud CLI non trouvé" -ForegroundColor Red
        Write-Host "   💡 Téléchargez-le: https://cloud.google.com/sdk/docs/install" -ForegroundColor Yellow
        exit 1
    }
} catch {
    Write-Host "   ❌ gcloud CLI non installé" -ForegroundColor Red
    Write-Host "   💡 Téléchargez-le: https://cloud.google.com/sdk/docs/install" -ForegroundColor Yellow
    exit 1
}

Write-Host ""
Write-Host "🔐 Configuration du projet..." -ForegroundColor Yellow
gcloud config set project $projectId

Write-Host ""
Write-Host "🔑 Authentification (ouvrir le navigateur)..." -ForegroundColor Yellow
gcloud auth login

Write-Host ""
Write-Host "🚀 Activation des APIs Vertex AI..." -ForegroundColor Green

$apis = @(
    "aiplatform.googleapis.com",           # API principale Vertex AI
    "ml.googleapis.com",                   # Machine Learning API
    "compute.googleapis.com",              # Compute Engine (requis)
    "storage.googleapis.com",              # Cloud Storage
    "bigquery.googleapis.com",             # BigQuery (pour les données)
    "containerregistry.googleapis.com"     # Container Registry
)

foreach ($api in $apis) {
    Write-Host "   🔧 Activation de $api..." -ForegroundColor Cyan
    gcloud services enable $api --project=$projectId
    if ($LASTEXITCODE -eq 0) {
        Write-Host "   ✅ $api activée" -ForegroundColor Green
    } else {
        Write-Host "   ❌ Erreur lors de l'activation de $api" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "📊 Vérification des modèles Vertex AI disponibles..." -ForegroundColor Yellow
Write-Host "   Région: $region" -ForegroundColor White

# Lister les modèles disponibles
gcloud ai models list --region=$region --project=$projectId --format="table(name,displayName)"

Write-Host ""
Write-Host "🎯 TEST DE VERTEX AI" -ForegroundColor Green
Write-Host "===================" -ForegroundColor Green

# Test simple avec curl
$testPrompt = "Hello, this is a test of Vertex AI Gemini"
$endpoint = "https://$region-aiplatform.googleapis.com/v1/projects/$projectId/locations/$region/publishers/google/models/gemini-1.5-pro:generateContent"

Write-Host "   🧪 Test endpoint: $endpoint" -ForegroundColor Cyan
Write-Host "   📝 Prompt de test: $testPrompt" -ForegroundColor White

# Obtenir le token d'accès
$accessToken = gcloud auth print-access-token

if ($accessToken) {
    Write-Host "   ✅ Token d'accès obtenu" -ForegroundColor Green
    
    # Test avec curl (si disponible)
    try {
        Write-Host "   🚀 Test d'appel API..." -ForegroundColor Yellow
        
        $body = @{
            contents = @(
                @{
                    parts = @(
                        @{
                            text = $testPrompt
                        }
                    )
                }
            )
        } | ConvertTo-Json -Depth 3

        $headers = @{
            "Authorization" = "Bearer $accessToken"
            "Content-Type" = "application/json"
        }

        $response = Invoke-RestMethod -Uri $endpoint -Method Post -Body $body -Headers $headers
        
        if ($response) {
            Write-Host "   🎉 VERTEX AI FONCTIONNE!" -ForegroundColor Green
            Write-Host "   ✅ Réponse reçue de Gemini" -ForegroundColor Green
        }
    } catch {
        Write-Host "   ⚠️ Test échoué, mais l'API pourrait être activée" -ForegroundColor Yellow
        Write-Host "   💡 Erreur: $($_.Exception.Message)" -ForegroundColor Yellow
    }
} else {
    Write-Host "   ❌ Impossible d'obtenir le token d'accès" -ForegroundColor Red
}

Write-Host ""
Write-Host "✅ ACTIVATION TERMINÉE!" -ForegroundColor Green
Write-Host "Vous pouvez maintenant relancer votre application .NET" -ForegroundColor White
Write-Host ""