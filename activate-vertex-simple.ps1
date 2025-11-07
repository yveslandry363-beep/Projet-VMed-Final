# Activation simple des APIs Vertex AI
Write-Host "🚀 ACTIVATION VERTEX AI - TECHNOLOGIE DE POINTE" -ForegroundColor Green

$projectId = "prototypevmed237"

Write-Host "Configuration du projet: $projectId"
gcloud config set project $projectId

Write-Host "Authentification..."
gcloud auth login

Write-Host "Activation de l'API Vertex AI..."
gcloud services enable aiplatform.googleapis.com --project=$projectId

Write-Host "Activation de l'API ML..."
gcloud services enable ml.googleapis.com --project=$projectId

Write-Host "Activation de l'API Compute..."
gcloud services enable compute.googleapis.com --project=$projectId

Write-Host "Test des modèles disponibles..."
gcloud ai models list --region=us-central1 --project=$projectId

Write-Host "✅ Activation terminée!"