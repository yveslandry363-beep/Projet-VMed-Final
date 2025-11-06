# Script de déploiement du connecteur Debezium
# Auteur: Configuration automatique
# Date: 2025-11-06

param(
    [string]$KafkaConnectUrl = "http://localhost:8083",
    [string]$ConnectorName = "postgres-diagnostics-connector"
)

Write-Host "🚀 Déploiement du connecteur Debezium" -ForegroundColor Cyan
Write-Host "=" * 60 -ForegroundColor Cyan

# Vérifier que le fichier de configuration existe
$configFile = "debezium-connector-config.json"
if (-not (Test-Path $configFile)) {
    Write-Host "❌ Fichier de configuration introuvable: $configFile" -ForegroundColor Red
    exit 1
}

Write-Host "`n📋 Configuration:" -ForegroundColor Yellow
Write-Host "   Kafka Connect URL: $KafkaConnectUrl" -ForegroundColor Gray
Write-Host "   Connecteur: $ConnectorName" -ForegroundColor Gray
Write-Host "   Fichier config: $configFile" -ForegroundColor Gray

# Charger la configuration
$config = Get-Content $configFile -Raw

# Vérifier si Kafka Connect est accessible
Write-Host "`n🔍 Vérification de Kafka Connect..." -ForegroundColor Cyan
try {
    $response = Invoke-WebRequest -Uri "$KafkaConnectUrl/" -Method Get -TimeoutSec 5 -ErrorAction Stop
    Write-Host "   ✅ Kafka Connect est accessible (HTTP $($response.StatusCode))" -ForegroundColor Green
} catch {
    Write-Host "   ❌ Kafka Connect n'est pas accessible à $KafkaConnectUrl" -ForegroundColor Red
    Write-Host "   Assurez-vous que Kafka Connect est démarré" -ForegroundColor Yellow
    Write-Host "`n💡 Pour démarrer Kafka Connect:" -ForegroundColor Cyan
    Write-Host "   docker-compose up -d kafka-connect" -ForegroundColor Gray
    Write-Host "   ou" -ForegroundColor Gray
    Write-Host "   bin/connect-distributed.sh config/connect-distributed.properties" -ForegroundColor Gray
    exit 1
}

# Vérifier si le connecteur existe déjà
Write-Host "`n🔍 Vérification du connecteur existant..." -ForegroundColor Cyan
try {
    $existingConnector = Invoke-WebRequest -Uri "$KafkaConnectUrl/connectors/$ConnectorName" -Method Get -ErrorAction Stop
    Write-Host "   ⚠️  Le connecteur '$ConnectorName' existe déjà" -ForegroundColor Yellow
    
    # Demander confirmation pour supprimer
    $confirm = Read-Host "   Voulez-vous le supprimer et recréer? (O/N)"
    if ($confirm -eq "O" -or $confirm -eq "o") {
        Write-Host "   🗑️  Suppression du connecteur..." -ForegroundColor Cyan
        Invoke-WebRequest -Uri "$KafkaConnectUrl/connectors/$ConnectorName" -Method Delete | Out-Null
        Write-Host "   ✅ Connecteur supprimé" -ForegroundColor Green
        Start-Sleep -Seconds 2
    } else {
        Write-Host "   ⏭️  Annulation du déploiement" -ForegroundColor Yellow
        exit 0
    }
} catch {
    Write-Host "   ✅ Aucun connecteur existant" -ForegroundColor Green
}

# Déployer le connecteur
Write-Host "`n🚀 Déploiement du connecteur..." -ForegroundColor Cyan
try {
    $headers = @{
        "Content-Type" = "application/json"
    }
    
    $response = Invoke-WebRequest `
        -Uri "$KafkaConnectUrl/connectors" `
        -Method Post `
        -Headers $headers `
        -Body $config `
        -ErrorAction Stop
    
    Write-Host "   ✅ Connecteur déployé avec succès!" -ForegroundColor Green
    
    # Afficher les détails
    $connectorInfo = $response.Content | ConvertFrom-Json
    Write-Host "`n📊 Détails du connecteur:" -ForegroundColor Cyan
    Write-Host "   Nom: $($connectorInfo.name)" -ForegroundColor Gray
    Write-Host "   Type: $($connectorInfo.config.'connector.class')" -ForegroundColor Gray
    Write-Host "   Table: $($connectorInfo.config.'table.include.list')" -ForegroundColor Gray
    
} catch {
    Write-Host "   ❌ Erreur lors du déploiement" -ForegroundColor Red
    Write-Host "   Détails: $($_.Exception.Message)" -ForegroundColor Yellow
    
    if ($_.Exception.Response) {
        $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
        $errorBody = $reader.ReadToEnd()
        Write-Host "`n📄 Réponse du serveur:" -ForegroundColor Yellow
        Write-Host $errorBody -ForegroundColor Gray
    }
    exit 1
}

# Vérifier le statut du connecteur
Write-Host "`n🔍 Vérification du statut..." -ForegroundColor Cyan
Start-Sleep -Seconds 3

try {
    $statusResponse = Invoke-WebRequest -Uri "$KafkaConnectUrl/connectors/$ConnectorName/status" -Method Get
    $status = $statusResponse.Content | ConvertFrom-Json
    
    Write-Host "`n📊 Statut du connecteur:" -ForegroundColor Cyan
    Write-Host "   État: $($status.connector.state)" -ForegroundColor $(if ($status.connector.state -eq "RUNNING") { "Green" } else { "Red" })
    Write-Host "   Worker: $($status.connector.worker_id)" -ForegroundColor Gray
    
    if ($status.tasks.Count -gt 0) {
        Write-Host "`n📋 Tâches:" -ForegroundColor Cyan
        foreach ($task in $status.tasks) {
            Write-Host "   Task $($task.id): $($task.state)" -ForegroundColor $(if ($task.state -eq "RUNNING") { "Green" } else { "Red" })
            if ($task.trace) {
                Write-Host "     Erreur: $($task.trace)" -ForegroundColor Red
            }
        }
    }
    
    if ($status.connector.state -eq "RUNNING") {
        Write-Host "`n✅ Le connecteur fonctionne correctement!" -ForegroundColor Green
    } else {
        Write-Host "`n⚠️  Le connecteur n'est pas en état RUNNING" -ForegroundColor Yellow
        Write-Host "   Consultez les logs Kafka Connect pour plus de détails" -ForegroundColor Gray
    }
    
} catch {
    Write-Host "   ❌ Erreur lors de la vérification du statut" -ForegroundColor Red
}

Write-Host "`n💡 Commandes utiles:" -ForegroundColor Cyan
Write-Host "   Liste des connecteurs: curl $KafkaConnectUrl/connectors" -ForegroundColor Gray
Write-Host "   Statut: curl $KafkaConnectUrl/connectors/$ConnectorName/status" -ForegroundColor Gray
Write-Host "   Supprimer: curl -X DELETE $KafkaConnectUrl/connectors/$ConnectorName" -ForegroundColor Gray
Write-Host "   Redémarrer: curl -X POST $KafkaConnectUrl/connectors/$ConnectorName/restart" -ForegroundColor Gray

Write-Host "`n" + ("=" * 60) -ForegroundColor Cyan
Write-Host "✅ Script terminé" -ForegroundColor Green
Write-Host ("=" * 60) -ForegroundColor Cyan
