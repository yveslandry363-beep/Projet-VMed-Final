param(
    [string]$Text = "Test CDC $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
    [string]$Guidance = "Validation Debezium → Kafka → App"
)

Write-Host "🧪 QUICK INSERT CDC" -ForegroundColor Cyan

# Read connection string from appsettings.json
$appsettingsPath = Join-Path (Get-Location) 'appsettings.json'
if (-not (Test-Path $appsettingsPath)) {
    Write-Error "appsettings.json introuvable dans $(Get-Location)"; exit 1
}

try {
    $json = Get-Content $appsettingsPath -Raw | ConvertFrom-Json
    $cs = $json.PostgreSql.ConnectionString
    if (-not $cs) { throw "ConnectionString manquant dans appsettings.json" }
} catch {
    Write-Error "Impossible de lire la chaîne de connexion: $($_.Exception.Message)"; exit 1
}

# Load Npgsql from bin
$npgsql = Get-ChildItem -Path ".\bin\Debug\net9.0" -Filter "Npgsql.dll" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $npgsql) { Write-Error "Npgsql.dll introuvable. Faites 'dotnet build' d'abord."; exit 1 }

Add-Type -Path $npgsql.FullName

$conn = New-Object Npgsql.NpgsqlConnection($cs)
try {
    $conn.Open()
    $sql = @"
INSERT INTO public.diagnostics (diagnostic_text, ia_guidance)
VALUES (@text, @guidance)
RETURNING id, date_creation;
"@
    $cmd = $conn.CreateCommand()
    $cmd.CommandText = $sql
    $cmd.Parameters.AddWithValue("text", $Text) | Out-Null
    $cmd.Parameters.AddWithValue("guidance", $Guidance) | Out-Null
    $reader = $cmd.ExecuteReader()
    if ($reader.Read()) {
        $id = $reader.GetInt32(0)
        $dt = $reader.GetDateTime(1)
        Write-Host "✅ Insert ID=$id Date=$dt" -ForegroundColor Green
    }
    $reader.Close()
} catch {
    Write-Error "Insertion échouée: $($_.Exception.Message)"; exit 1
} finally {
    if ($conn.State -eq 'Open') { $conn.Close() }
}

Write-Host "🏁 Terminé" -ForegroundColor Cyan
