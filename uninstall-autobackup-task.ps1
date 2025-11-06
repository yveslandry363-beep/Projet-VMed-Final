$taskName = "AutoBackupAgent"
try {
  Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction Stop
  Write-Host "Scheduled Task '$taskName' removed." -ForegroundColor Green
} catch {
  Write-Host "Task '$taskName' not found or already removed." -ForegroundColor Yellow
}