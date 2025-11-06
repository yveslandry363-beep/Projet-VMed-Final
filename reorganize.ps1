# Début du script reorganize.ps1

Write-Host "--- Début de la réorganisation du projet ---" -ForegroundColor Yellow

$rootDir = $PSScriptRoot
$fileList = Get-ChildItem -Recurse -Filter *.cs -Path $rootDir | Where-Object { $_.FullName -notlike "*\obj\*" -and $_.FullName -notlike "*\bin\*" }

# 1. Définir la "carte" de destination pour chaque fichier
# Clé = Nom du Fichier, Valeur = Nom du Dossier de destination
$fileMap = @{
    "GeminiApiService.cs" = "Services"
    "KafkaConsumerService.cs" = "Services"
    "KafkaProducer.cs" = "Services"
    "PostgreSqlConnector.cs" = "Connectors"
    "IADatabaseConnector.cs" = "Interfaces" # (Nous gérerons le renommage plus tard)
    "IDatabaseConnector.cs" = "Interfaces"
    "IDbConnectionFactory.cs" = "Interfaces"
    "IGeminiApiService.cs" = "Interfaces"
    "IKafkaProducer.cs" = "Interfaces"
    "GeminiDtos.cs" = "Models"
    "KafkaPayloads.cs" = "Models"
    "Telemetry.cs" = "Helpers"
    "JsonContext.cs" = "Serialization"
    "KafkaSettings.cs" = "Settings"
    "GoogleCloudSettings.cs" = "Settings"
    "PostgreSqlSettings.cs" = "Settings"
    "RetryPolicyConfig.cs" = "Settings"
    "RetryPoliciesSettings.cs" = "Settings"
    "KafkaSettingsValidator.cs" = "Validation"
}

# 2. Créer les dossiers de destination (s'ils n'existent pas)
Write-Host "Création des dossiers de destination..."
$fileMap.Values | Get-Unique | ForEach-Object {
    $newDir = Join-Path $rootDir $_
    if (-not (Test-Path $newDir)) {
        New-Item -ItemType Directory -Path $newDir
        Write-Host "  [CRÉÉ] $newDir" -ForegroundColor Green
    }
}

Write-Host "Déplacement et correction des fichiers..."

# 3. Boucler sur tous les fichiers C# trouvés
foreach ($file in $fileList) {
    
    # Ignorer les fichiers déjà bien placés (sauf s'ils sont à la racine)
    if ($file.DirectoryName -eq $rootDir -and ($file.Name -eq "Program.cs" -or $file.Name -eq "GlobalUsings.cs")) {
        continue
    }

    # Trouver la destination
    $targetFolder = $fileMap[$file.Name]

    if ($targetFolder) {
        $targetNamespace = "PrototypeGemini.$targetFolder"
        $newPath = Join-Path (Join-Path $rootDir $targetFolder) $file.Name

        # Lire le contenu du fichier
        $content = Get-Content $file.FullName -Raw

        # Remplacer le namespace (la partie la plus importante)
        $newContent = $content -replace 'namespace .*(?={)', "namespace $targetNamespace"
        
        # Écrire le nouveau contenu au bon endroit
        Set-Content -Path $newPath -Value $newContent -Encoding UTF8
        Write-Host "  [CORRIGÉ] $($file.Name) -> $targetNamespace" -ForegroundColor Cyan

        # Supprimer l'ancien fichier s'il est différent
        if ($file.FullName -ne $newPath) {
            Remove-Item $file.FullName
            Write-Host "  [DÉPLACÉ] $($file.FullName)" -ForegroundColor Gray
        }
    }
}

Write-Host "--- Réorganisation terminée ---" -ForegroundColor Yellow
Write-Host "Veuillez maintenant exécuter 'dotnet build' pour vérifier."
# Fin du script