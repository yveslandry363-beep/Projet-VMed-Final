#!/usr/bin/env pwsh
# Verification de l'acces Vertex AI et des modeles Gemini disponibles

Write-Host ""
Write-Host "=== VERIFICATION VERTEX AI ===" -ForegroundColor Cyan
Write-Host ""

# Charger la config
$config = Get-Content "appsettings.json" -Raw | ConvertFrom-Json
$projectId = $config.GoogleCloud.ProjectId
$location = $config.GoogleCloud.LocationId

Write-Host "Projet: $projectId" -ForegroundColor Yellow
Write-Host "Region: $location" -ForegroundColor Yellow
Write-Host ""

# Verifier gcloud
try {
    $gcloudVersion = gcloud version 2>&1 | Select-String "Google Cloud SDK"
    Write-Host "gcloud CLI: $gcloudVersion" -ForegroundColor Green
} catch {
    Write-Host "ERREUR: gcloud CLI non installe" -ForegroundColor Red
    Write-Host "Installez depuis: https://cloud.google.com/sdk/docs/install" -ForegroundColor Yellow
    exit 1
}

Write-Host ""
Write-Host "--- Etape 1: Verifier l'API Vertex AI ---" -ForegroundColor Cyan

# Verifier si l'API est activee
Write-Host "Verification de l'API aiplatform.googleapis.com..." -ForegroundColor Yellow
$apiCheck = gcloud services list --enabled --project=$projectId --filter="name:aiplatform.googleapis.com" --format="value(name)" 2>&1

if ($apiCheck -like "*aiplatform.googleapis.com*") {
    Write-Host "  API Vertex AI: ACTIVEE" -ForegroundColor Green
} else {
    Write-Host "  API Vertex AI: NON ACTIVEE" -ForegroundColor Red
    Write-Host ""
    Write-Host "Voulez-vous activer l'API maintenant? (O/N): " -NoNewline -ForegroundColor Yellow
    $response = Read-Host
    
    if ($response -eq "O" -or $response -eq "o") {
        Write-Host "Activation de l'API..." -ForegroundColor Yellow
        gcloud services enable aiplatform.googleapis.com --project=$projectId
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "  API activee avec succes" -ForegroundColor Green
        } else {
            Write-Host "  ERREUR lors de l'activation" -ForegroundColor Red
            exit 1
        }
    } else {
        Write-Host "Activation annulee. L'API doit etre activee pour continuer." -ForegroundColor Red
        exit 1
    }
}

Write-Host ""
Write-Host "--- Etape 2: Lister les modeles Gemini disponibles ---" -ForegroundColor Cyan

# Essayer de lister les modeles
Write-Host "Recherche des modeles dans $location..." -ForegroundColor Yellow

# Utiliser l'API REST directement
$serviceAccount = Get-Content "gcp-key.json" -Raw | ConvertFrom-Json
$saEmail = $serviceAccount.client_email

Write-Host "Service Account: $saEmail" -ForegroundColor Yellow
Write-Host ""

# Obtenir un token d'acces
Write-Host "Obtention du token OAuth2..." -ForegroundColor Yellow
$token = gcloud auth application-default print-access-token 2>&1

if ($LASTEXITCODE -ne 0) {
    Write-Host "  ERREUR: Impossible d'obtenir le token" -ForegroundColor Red
    Write-Host "  Executez: gcloud auth application-default login" -ForegroundColor Yellow
    exit 1
}

Write-Host "  Token obtenu" -ForegroundColor Green
Write-Host ""

# Tester differents endpoints
$endpoints = @(
    "https://$location-aiplatform.googleapis.com/v1/projects/$projectId/locations/$location/publishers/google/models",
    "https://$location-aiplatform.googleapis.com/v1/projects/$projectId/locations/$location/models"
)

foreach ($endpoint in $endpoints) {
    Write-Host "Test: $endpoint" -ForegroundColor Yellow
    
    try {
        $headers = @{
            "Authorization" = "Bearer $token"
            "Content-Type" = "application/json"
        }
        
        $response = Invoke-RestMethod -Uri $endpoint -Headers $headers -Method Get -ErrorAction Stop
        
        Write-Host "  Succes! Modeles trouves:" -ForegroundColor Green
        
        if ($response.models) {
            $response.models | ForEach-Object {
                $modelName = $_.name -replace ".*/", ""
                Write-Host "    - $modelName" -ForegroundColor Cyan
            }
        } else {
            Write-Host "    Aucun modele retourne" -ForegroundColor Yellow
        }
        
    } catch {
        $statusCode = $_.Exception.Response.StatusCode.Value__
        Write-Host "  Erreur $statusCode : $($_.Exception.Message)" -ForegroundColor Red
    }
    
    Write-Host ""
}

Write-Host "--- Etape 3: Tester des modeles specifiques ---" -ForegroundColor Cyan

$modelsToTest = @(
    "gemini-1.5-pro",
    "gemini-1.5-flash",
    "gemini-pro",
    "gemini-1.0-pro"
)

foreach ($model in $modelsToTest) {
    $testUrl = "https://$location-aiplatform.googleapis.com/v1/projects/$projectId/locations/$location/publishers/google/models/$model"
    
    Write-Host "Test: $model" -ForegroundColor Yellow
    
    try {
        $headers = @{
            "Authorization" = "Bearer $token"
        }
        
        $response = Invoke-RestMethod -Uri $testUrl -Headers $headers -Method Get -ErrorAction Stop
        Write-Host "  DISPONIBLE" -ForegroundColor Green
        
    } catch {
        $statusCode = $_.Exception.Response.StatusCode.Value__
        
        if ($statusCode -eq 404) {
            Write-Host "  NON DISPONIBLE (404)" -ForegroundColor Red
        } else {
            Write-Host "  ERREUR $statusCode" -ForegroundColor Red
        }
    }
}

Write-Host ""
Write-Host "--- Etape 4: Verifier les permissions IAM ---" -ForegroundColor Cyan

Write-Host "Verification des roles du Service Account..." -ForegroundColor Yellow

$iamPolicy = gcloud projects get-iam-policy $projectId --flatten="bindings[].members" --format="table(bindings.role)" --filter="bindings.members:$saEmail" 2>&1

Write-Host ""
Write-Host "Roles actuels pour $saEmail :" -ForegroundColor Yellow
Write-Host $iamPolicy

Write-Host ""
Write-Host "=== RECOMMANDATIONS ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "1. Si aucun modele n'est disponible, essayez une autre region:" -ForegroundColor Yellow
Write-Host "   - us-central1 (USA)" -ForegroundColor White
Write-Host "   - europe-west1 (Belgique)" -ForegroundColor White
Write-Host "   - asia-northeast1 (Tokyo)" -ForegroundColor White
Write-Host ""
Write-Host "2. Assurez-vous que le Service Account a le role:" -ForegroundColor Yellow
Write-Host "   roles/aiplatform.user" -ForegroundColor White
Write-Host ""
Write-Host "   Commande pour ajouter:" -ForegroundColor White
Write-Host "   gcloud projects add-iam-policy-binding $projectId \\" -ForegroundColor Gray
Write-Host "     --member='serviceAccount:$saEmail' \\" -ForegroundColor Gray
Write-Host "     --role='roles/aiplatform.user'" -ForegroundColor Gray
Write-Host ""
Write-Host "3. Verifiez la documentation des modeles disponibles:" -ForegroundColor Yellow
Write-Host "   https://cloud.google.com/vertex-ai/generative-ai/docs/learn/models" -ForegroundColor White
Write-Host ""
