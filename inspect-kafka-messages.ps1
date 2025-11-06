# Script: inspect-kafka-messages.ps1
# Inspecte les messages Kafka pour déboguer le format Debezium

Write-Host "🔍 Inspection des messages Kafka depuis Aiven Console" -ForegroundColor Cyan
Write-Host ("=" * 70)

Write-Host "`n📋 Les 2 messages du topic pg_diagnostics.public.diagnostics :" -ForegroundColor Yellow

Write-Host "`nMESSAGE 1 (Offset 0) - Format attendu:"
$message1 = @"
{
  "schema": { ... },
  "payload": {
    "before": null,
    "after": {
      "id": 1,
      "diagnostic_text": "...",
      "ia_guidance": "...",
      "date_creation": "...",
      "created_by": "...",
      "updated_at": "..."
    },
    "source": { ... },
    "op": "c",
    "ts_ms": 1234567890
  }
}
"@
Write-Host $message1 -ForegroundColor Green

Write-Host "`n⚠️  PROBLÈME DÉTECTÉ :" -ForegroundColor Red
Write-Host "Le code cherche 'msg.after' mais Debezium envoie 'msg.payload.after'"

Write-Host "`n💡 SOLUTIONS POSSIBLES :" -ForegroundColor Yellow
Write-Host "1. Modifier le modèle DebeziumPayload pour inclure 'payload'"
Write-Host "2. Vérifier le format réel dans Aiven Console"
Write-Host "3. Activer le mode 'unwrap' dans Debezium (envoie seulement 'after')"

Write-Host "`n🔧 Pour vérifier le format réel :" -ForegroundColor Cyan
Write-Host "1. Allez sur https://console.aiven.io"
Write-Host "2. Service 'ia-kafka-bus' → Topics"
Write-Host "3. Topic 'pg_diagnostics.public.diagnostics' → Messages"
Write-Host "4. Cliquez sur 'Fetch messages' et copiez le JSON complet ici"

Write-Host "`n📝 Collez le JSON du premier message ci-dessous (Ctrl+V puis Enter 2x):"
$userInput = @()
do {
    $line = Read-Host
    if ($line) { $userInput += $line }
} while ($line)

if ($userInput.Count -gt 0) {
    $jsonText = $userInput -join "`n"
    
    try {
        $parsed = $jsonText | ConvertFrom-Json
        
        Write-Host "`n✅ JSON valide détecté !" -ForegroundColor Green
        Write-Host "`n🔍 Structure du message :"
        
        if ($parsed.payload) {
            Write-Host "  ✅ Champ 'payload' trouvé" -ForegroundColor Green
            if ($parsed.payload.after) {
                Write-Host "  ✅ Champ 'payload.after' trouvé" -ForegroundColor Green
                Write-Host "`n📄 Contenu de 'payload.after' :"
                $parsed.payload.after | ConvertTo-Json -Depth 10 | Write-Host -ForegroundColor Cyan
                
                Write-Host "`n✅ FORMAT CORRECT ! Modifiez DebeziumPayload ainsi :" -ForegroundColor Green
                Write-Host @"
public class DebeziumMessage<T> where T : class
{
    [JsonPropertyName("payload")]
    public DebeziumPayload<T>? payload { get; set; }
}

public class DebeziumPayload<T> where T : class
{
    [JsonPropertyName("before")]
    public T? before { get; set; }

    [JsonPropertyName("after")]
    public T? after { get; set; }
}
"@ -ForegroundColor Yellow
            }
            elseif ($parsed.payload.GetType().Name -ne "PSCustomObject") {
                Write-Host "  ⚠️  'payload' n'est pas un objet" -ForegroundColor Red
            }
            else {
                Write-Host "  ❌ Champ 'payload.after' manquant" -ForegroundColor Red
                Write-Host "  Contenu de 'payload' :" -ForegroundColor Yellow
                $parsed.payload | ConvertTo-Json -Depth 10 | Write-Host
            }
        }
        elseif ($parsed.after) {
            Write-Host "  ✅ Champ 'after' trouvé directement (mode unwrap)" -ForegroundColor Green
            Write-Host "`n📄 Contenu de 'after' :"
            $parsed.after | ConvertTo-Json -Depth 10 | Write-Host -ForegroundColor Cyan
            
            Write-Host "`n✅ FORMAT UNWRAPPED ! Le modèle actuel devrait fonctionner." -ForegroundColor Green
        }
        else {
            Write-Host "  ❌ Structure inconnue" -ForegroundColor Red
            Write-Host "  Contenu complet :" -ForegroundColor Yellow
            $parsed | ConvertTo-Json -Depth 10 | Write-Host
        }
    }
    catch {
        Write-Host "`n❌ JSON invalide : $($_.Exception.Message)" -ForegroundColor Red
    }
}
else {
    Write-Host "`n⚠️  Aucun JSON collé. Vérifiez manuellement dans Aiven Console." -ForegroundColor Yellow
}

Write-Host "`n" ("=" * 70)
Write-Host "Script terminé. Appuyez sur une touche pour quitter..."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
