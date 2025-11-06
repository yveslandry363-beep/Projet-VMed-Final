# Script de diagnostic Kafka Connect via API REST
# Interroge l'API Aiven Kafka Connect pour obtenir le statut détaillé

Write-Host "🔍 Diagnostic Kafka Connect - Connecteur Debezium" -ForegroundColor Cyan
Write-Host ("=" * 70) -ForegroundColor Cyan

# Configuration Aiven (à adapter si nécessaire)
$KAFKA_CONNECT_URL = "https://ia-kafka-connect-yveslandry363-974a.aivencloud.com:443"
$CONNECTOR_NAME = "debezium-pg-source-diagnostics"

Write-Host "`n⚠️  NOTE: Ce script nécessite l'URL publique de votre Kafka Connect Aiven" -ForegroundColor Yellow
Write-Host "   Si l'URL ci-dessus est incorrecte, modifiez la variable KAFKA_CONNECT_URL" -ForegroundColor Gray

# Fonction pour faire des requêtes HTTP
function Get-KafkaConnectInfo {
    param(
        [string]$Endpoint,
        [string]$Description
    )
    
    Write-Host "`n📊 $Description..." -ForegroundColor Cyan
    
    try {
        $url = "$KAFKA_CONNECT_URL$Endpoint"
        Write-Host "   URL: $url" -ForegroundColor Gray
        
        $response = Invoke-RestMethod -Uri $url -Method Get -ErrorAction Stop
        
        Write-Host "   ✅ Réponse reçue" -ForegroundColor Green
        
        # Afficher la réponse formatée
        $json = $response | ConvertTo-Json -Depth 10
        Write-Host $json -ForegroundColor White
        
        return $response
    }
    catch {
        Write-Host "   ❌ Erreur: $($_.Exception.Message)" -ForegroundColor Red
        
        if ($_.Exception.Response) {
            $statusCode = $_.Exception.Response.StatusCode.value__
            Write-Host "   Code HTTP: $statusCode" -ForegroundColor Yellow
        }
        
        return $null
    }
}

# 1. Lister tous les connecteurs
Write-Host "`n" + ("=" * 70) -ForegroundColor Cyan
$connectors = Get-KafkaConnectInfo -Endpoint "/connectors" -Description "Liste des connecteurs"

if ($connectors -and $connectors.Count -gt 0) {
    Write-Host "`n✅ Connecteurs trouvés: $($connectors -join ', ')" -ForegroundColor Green
} else {
    Write-Host "`n❌ Aucun connecteur trouvé" -ForegroundColor Red
}

# 2. Obtenir le statut du connecteur Debezium
Write-Host "`n" + ("=" * 70) -ForegroundColor Cyan
$status = Get-KafkaConnectInfo -Endpoint "/connectors/$CONNECTOR_NAME/status" -Description "Statut du connecteur $CONNECTOR_NAME"

if ($status) {
    Write-Host "`n📊 ANALYSE DU STATUT:" -ForegroundColor Cyan
    Write-Host "   Connecteur: $($status.name)" -ForegroundColor White
    Write-Host "   État: $($status.connector.state)" -ForegroundColor $(if ($status.connector.state -eq "RUNNING") { "Green" } else { "Red" })
    Write-Host "   Worker: $($status.connector.worker_id)" -ForegroundColor Gray
    
    if ($status.tasks) {
        Write-Host "`n   Tâches:" -ForegroundColor Cyan
        foreach ($task in $status.tasks) {
            $taskStatus = if ($task.state -eq "RUNNING") { "Green" } else { "Red" }
            Write-Host "     Task $($task.id): $($task.state)" -ForegroundColor $taskStatus
            
            if ($task.trace) {
                Write-Host "     ⚠️  Erreur détectée:" -ForegroundColor Red
                Write-Host $task.trace -ForegroundColor Yellow
            }
        }
    }
}

# 3. Obtenir la configuration du connecteur
Write-Host "`n" + ("=" * 70) -ForegroundColor Cyan
$config = Get-KafkaConnectInfo -Endpoint "/connectors/$CONNECTOR_NAME/config" -Description "Configuration du connecteur $CONNECTOR_NAME"

if ($config) {
    Write-Host "`n📋 CONFIGURATION ACTUELLE:" -ForegroundColor Cyan
    Write-Host "   Database: $($config.'database.hostname'):$($config.'database.port')" -ForegroundColor White
    Write-Host "   Table: $($config.'table.include.list')" -ForegroundColor White
    Write-Host "   Publication: $($config.'publication.name')" -ForegroundColor White
    Write-Host "   Topic Prefix: $($config.'topic.prefix')" -ForegroundColor White
    Write-Host "   Snapshot Mode: $($config.'snapshot.mode')" -ForegroundColor White
}

# 4. Obtenir les topics du connecteur
Write-Host "`n" + ("=" * 70) -ForegroundColor Cyan
$topics = Get-KafkaConnectInfo -Endpoint "/connectors/$CONNECTOR_NAME/topics" -Description "Topics du connecteur $CONNECTOR_NAME"

if ($topics) {
    Write-Host "`n📬 TOPICS KAFKA:" -ForegroundColor Cyan
    if ($topics.$CONNECTOR_NAME -and $topics.$CONNECTOR_NAME.topics) {
        foreach ($topic in $topics.$CONNECTOR_NAME.topics) {
            Write-Host "   - $topic" -ForegroundColor White
        }
    } else {
        Write-Host "   ⚠️  Aucun topic trouvé - Le connecteur n'a peut-être pas encore capturé de données" -ForegroundColor Yellow
    }
}

Write-Host "`n" + ("=" * 70) -ForegroundColor Cyan
Write-Host "✅ Diagnostic terminé" -ForegroundColor Green
Write-Host ("=" * 70) -ForegroundColor Cyan

Write-Host "`n💡 PROCHAINES ÉTAPES:" -ForegroundColor Yellow

if ($status -and $status.connector.state -ne "RUNNING") {
    Write-Host "   1. Le connecteur n'est pas en état RUNNING" -ForegroundColor Red
    Write-Host "   2. Vérifiez les erreurs ci-dessus" -ForegroundColor Gray
    Write-Host "   3. Vérifiez dans Aiven Console → Logs pour plus de détails" -ForegroundColor Gray
} elseif (-not $topics -or -not $topics.$CONNECTOR_NAME.topics -or $topics.$CONNECTOR_NAME.topics.Count -eq 0) {
    Write-Host "   1. Le connecteur est RUNNING mais aucun topic n'est créé" -ForegroundColor Yellow
    Write-Host "   2. Vérifiez que la publication PostgreSQL existe:" -ForegroundColor Gray
    Write-Host "      SELECT * FROM pg_publication WHERE pubname = 'dbz_publication';" -ForegroundColor White
    Write-Host "   3. Vérifiez que la table a des données:" -ForegroundColor Gray
    Write-Host "      SELECT COUNT(*) FROM public.diagnostics;" -ForegroundColor White
    Write-Host "   4. Redémarrez le connecteur dans Aiven Console" -ForegroundColor Gray
} else {
    Write-Host "   ✅ Le connecteur semble fonctionner correctement!" -ForegroundColor Green
    Write-Host "   Insérez une donnée de test dans PostgreSQL pour vérifier CDC" -ForegroundColor Gray
}
