# Script: watch-cdc-logs.ps1
# Surveille la console C# en temps réel pour voir les messages CDC

Write-Host "👀 SURVEILLANCE DES LOGS CDC EN TEMPS RÉEL" -ForegroundColor Cyan
Write-Host ("=" * 70)
Write-Host ""
Write-Host "📋 Instructions:" -ForegroundColor Yellow
Write-Host "1. L'application C# doit être EN COURS (dotnet run)" -ForegroundColor White
Write-Host "2. Exécutez une insertion dans DBeaver:" -ForegroundColor White
Write-Host ""
Write-Host "   INSERT INTO diagnostics (diagnostic_text, ia_guidance)" -ForegroundColor Green
Write-Host "   VALUES ('Test CDC', 'Validation');" -ForegroundColor Green
Write-Host ""
Write-Host "3. Regardez ce terminal - les messages apparaîtront ICI!" -ForegroundColor White
Write-Host ""
Write-Host ("=" * 70)
Write-Host ""
Write-Host "⏳ En attente de messages CDC..." -ForegroundColor Yellow
Write-Host "   (Appuyez sur Ctrl+C pour arrêter)" -ForegroundColor Gray
Write-Host ""

# Filtre pour capturer uniquement les messages importants
$filter = "📬|🚨|TENTATIVE|Message reçu|SANTÉ|PROBLÈME|Debezium"

# Couleurs selon le type de message
function Write-ColoredLog {
    param($line)
    
    if ($line -match "📬") {
        Write-Host $line -ForegroundColor Green
    }
    elseif ($line -match "🚨|TENTATIVE|ATTAQUE") {
        Write-Host $line -ForegroundColor Red
    }
    elseif ($line -match "⚠️|PROBLÈME|WARNING") {
        Write-Host $line -ForegroundColor Yellow
    }
    elseif ($line -match "✅|Healthy") {
        Write-Host $line -ForegroundColor Cyan
    }
    elseif ($line -match "Message reçu") {
        Write-Host $line -ForegroundColor Magenta
    }
    else {
        Write-Host $line -ForegroundColor White
    }
}

# Surveille les processus dotnet run
$lastCheck = Get-Date
$messageCount = 0

try {
    while ($true) {
        # Vérifier que dotnet run est actif
        $dotnetProcess = Get-Process -Name "dotnet" -ErrorAction SilentlyContinue | 
                        Where-Object { $_.MainWindowTitle -like "*Prototype*" -or $_.CommandLine -like "*VMed327*" }
        
        if (-not $dotnetProcess) {
            Write-Host "`n⚠️  ATTENTION: Aucun processus 'dotnet run' détecté!" -ForegroundColor Red
            Write-Host "   Lancez d'abord: cd 'd:\VMed327\Prototype Gemini'; dotnet run" -ForegroundColor Yellow
            Start-Sleep -Seconds 5
            continue
        }
        
        # Afficher un heartbeat toutes les 30 secondes
        $now = Get-Date
        if (($now - $lastCheck).TotalSeconds -ge 30) {
            Write-Host "[$(Get-Date -Format 'HH:mm:ss')] 💓 En écoute... (Messages reçus: $messageCount)" -ForegroundColor DarkGray
            $lastCheck = $now
        }
        
        Start-Sleep -Milliseconds 500
    }
}
finally {
    Write-Host "`n🛑 Surveillance arrêtée." -ForegroundColor Yellow
}
