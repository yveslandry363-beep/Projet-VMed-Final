using System.Collections.Concurrent;
using System.Diagnostics;
using System.IO.Compression;
using System.Text;

internal static class Program
{
    private static readonly TimeSpan DebounceWindow = TimeSpan.FromSeconds(3);
    private static readonly HashSet<string> ScriptExtensions = new(StringComparer.OrdinalIgnoreCase)
    {
        ".cs", ".ps1", ".psm1", ".psd1", ".bat", ".cmd", ".sh", ".bash", ".zsh",
        ".ts", ".js", ".mjs", ".cjs", ".json", ".yml", ".yaml", ".toml", ".ini",
        ".py", ".rb", ".php", ".sql", ".xml", ".csproj", ".sln", ".md"
    };

    private static async Task<int> Main(string[] args)
    {
        Console.OutputEncoding = Encoding.UTF8;
        var watchPath = GetArg(args, "--path") ?? Environment.GetEnvironmentVariable("WATCH_PATH") ?? Directory.GetCurrentDirectory();
        var repoUrl = GetArg(args, "--repo") ?? Environment.GetEnvironmentVariable("REPO_URL");
        var branch = GetArg(args, "--branch") ?? Environment.GetEnvironmentVariable("BRANCH") ?? "main";
    var token = TokenProvider.TryGetToken();

        if (string.IsNullOrWhiteSpace(repoUrl))
        {
            Console.Error.WriteLine("[ERR] REPO_URL manquant. Définissez --repo ou la variable d'environnement REPO_URL.");
            return 2;
        }

        if (!GitRunner.IsGitAvailable(out var gitVersion))
        {
            Console.Error.WriteLine("[ERR] Git n'est pas installé ou introuvable dans le PATH.");
            return 3;
        }

        Console.WriteLine($"[OK] Git {gitVersion}");
        Console.WriteLine($"[OK] Dossier surveillé: {watchPath}");
        Console.WriteLine($"[OK] Branche: {branch}");

        // Initialiser le repo local si nécessaire
        if (!Directory.Exists(Path.Combine(watchPath, ".git")))
        {
            Console.WriteLine("[INIT] Initialisation du dépôt local...");
            if (await GitRunner.Run(watchPath, token, "init") != 0) return 10;
            if (await GitRunner.Run(watchPath, token, $"remote add origin {repoUrl}") != 0)
            {
                // Peut déjà exister
                await GitRunner.Run(watchPath, token, "remote set-url origin \"" + repoUrl + "\"");
            }

            // Configure minimal identity required for committing
            await GitRunner.Run(watchPath, token, "config user.name \"AutoBackupAgent\"");
            await GitRunner.Run(watchPath, token, "config user.email \"autobackup@localhost\"");
        }

        // Assurer la branche cible
        await GitRunner.Run(watchPath, token, $"checkout -B {branch}");

        // Premier push si la branche n'existe pas encore
        await GitRunner.Run(watchPath, token, $"pull --rebase origin {branch}");

        Console.WriteLine("[WATCH] Démarrage de la surveillance des modifications...");

        var queue = new ConcurrentQueue<DateTime>();
        using var fsw = new FileSystemWatcher(watchPath)
        {
            IncludeSubdirectories = true,
            Filter = "*.*",
            EnableRaisingEvents = true,
            NotifyFilter = NotifyFilters.FileName | NotifyFilters.LastWrite | NotifyFilters.DirectoryName | NotifyFilters.Size
        };

        void OnChange(object? s, FileSystemEventArgs e)
        {
            if (IsIgnored(e.FullPath, watchPath)) return;
            if (!IsScript(e.FullPath)) return; // Trigger only on script-like changes
            queue.Enqueue(DateTime.UtcNow);
        }

        fsw.Changed += OnChange;
        fsw.Created += OnChange;
        fsw.Deleted += OnChange;
    fsw.Renamed += (s, e) => { if (!IsIgnored(e.FullPath, watchPath) && IsScript(e.FullPath)) queue.Enqueue(DateTime.UtcNow); };

        var cts = new CancellationTokenSource();
        Console.CancelKeyPress += (s, e) => { e.Cancel = true; cts.Cancel(); };

        try
        {
            DateTime? lastFlush = null;
            while (!cts.IsCancellationRequested)
            {
                await Task.Delay(500, cts.Token);
                if (queue.IsEmpty) continue;

                // Debounce window
                var now = DateTime.UtcNow;
                lastFlush ??= now;
                if (now - lastFlush < DebounceWindow) continue;

                // Consume queue
                while (queue.TryDequeue(out _)) { }
                lastFlush = now;

                // Commit & push
                var changes = await GitRunner.RunCapture(watchPath, token, "status --porcelain");
                if (string.IsNullOrWhiteSpace(changes.StdOut))
                {
                    continue; // rien à faire
                }

                Console.WriteLine("[COMMIT] Modifications détectées. Préparation du commit...");
                var prevHead = (await GitRunner.RunCapture(watchPath, token, "rev-parse HEAD")).StdOut?.Trim();

                // Garde de sécurité: empêcher l'upload de secrets
                var secretAlert = await SecretGuard.CheckForSecretsAsync(watchPath, token);
                if (!string.IsNullOrEmpty(secretAlert))
                {
                    Console.Error.WriteLine($"[ABORT] Sécurité: {secretAlert}\nAjoutez ces fichiers à .gitignore. Commit/push annulé.");
                    // vider la queue pour éviter les boucles
                    while (queue.TryDequeue(out _)) { }
                    lastFlush = DateTime.UtcNow;
                    continue;
                }

                // Ajouter tous les fichiers sauf .git
                await GitRunner.Run(watchPath, token, "add -A");

                var msg = $"AutoBackup: {DateTimeOffset.Now:yyyy-MM-dd HH:mm:ss zzz}";
                var commitCode = await GitRunner.Run(watchPath, token, $"commit -m \"{EscapeQuotes(msg)}\"");
                if (commitCode != 0)
                {
                    Console.WriteLine($"[WARN] Commit a échoué (code {commitCode}). Vérifiez la configuration Git (user.name/user.email) ou l'état du staging.");
                    continue;
                }

                Console.WriteLine("[PUSH] Envoi des modifications vers origin...");
                if (await GitRunner.Run(watchPath, token, $"push origin {branch}") != 0)
                {
                    Console.Error.WriteLine("[ERR] Échec du push vers origin.");
                    continue;
                }

                // Backup de la version précédente si elle existe
                var previous = (await GitRunner.RunCapture(watchPath, token, "rev-parse HEAD~1")).StdOut?.Trim();
                if (!string.IsNullOrEmpty(previous))
                {
                    Console.WriteLine($"[BACKUP] Archivage du commit précédent {previous}...");
                    var tempZip = Path.Combine(Path.GetTempPath(), $"backup-{DateTime.UtcNow:yyyyMMdd-HHmmss}.zip");

                    // Exporter l'ancien arbre dans une archive
                    if (await GitRunner.Run(watchPath, token, $"archive -o \"{tempZip}\" {previous}") != 0)
                    {
                        Console.Error.WriteLine("[WARN] Impossible de créer l'archive de sauvegarde.");
                    }
                    else
                    {
                        // Commiter l'archive dans la branche backups
                        var currentBranch = (await GitRunner.RunCapture(watchPath, token, "rev-parse --abbrev-ref HEAD")).StdOut?.Trim();
                        await GitRunner.Run(watchPath, token, "fetch origin backups");
                        var checkoutBackups = await GitRunner.Run(watchPath, token, "checkout backups");
                        if (checkoutBackups != 0)
                        {
                            // créer une branche orpheline si elle n'existe pas
                            await GitRunner.Run(watchPath, token, "checkout --orphan backups");
                            // Nettoyer l'arbre
                            foreach (var file in Directory.EnumerateFileSystemEntries(watchPath))
                            {
                                if (Path.GetFileName(file).Equals(".git", StringComparison.OrdinalIgnoreCase)) continue;
                                try
                                {
                                    if (Directory.Exists(file)) Directory.Delete(file, true);
                                    else File.Delete(file);
                                }
                                catch { /* ignore */ }
                            }
                            await GitRunner.Run(watchPath, token, "commit --allow-empty -m \"Initialize backups branch\"");
                        }

                        Directory.CreateDirectory(Path.Combine(watchPath, "backups"));
                        var dest = Path.Combine(watchPath, "backups", Path.GetFileName(tempZip));
                        File.Copy(tempZip, dest, overwrite: true);

                        await GitRunner.Run(watchPath, token, "add backups");
                        await GitRunner.Run(watchPath, token, $"commit -m \"Backup of {previous} at {DateTime.UtcNow:O}\"");
                        await GitRunner.Run(watchPath, token, "push origin backups");

                        // Retour sur la branche d'origine
                        if (!string.IsNullOrWhiteSpace(currentBranch))
                        {
                            await GitRunner.Run(watchPath, token, $"checkout {currentBranch}");
                        }
                    }
                }
            }
        }
        catch (OperationCanceledException)
        {
            Console.WriteLine("[STOP] Arrêt demandé.");
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine($"[FATAL] {ex.Message}");
            return 1;
        }

        return 0;
    }

    private static bool IsIgnored(string path, string root)
    {
        // Ignorer .git et le dossier backups
        var rel = Path.GetRelativePath(root, path);
        if (rel.StartsWith(".git")) return true;
        if (rel.StartsWith("backups")) return true;
        return false;
    }

    private static bool IsScript(string path)
    {
        try
        {
            var ext = Path.GetExtension(path);
            if (string.IsNullOrEmpty(ext)) return false;
            return ScriptExtensions.Contains(ext);
        }
        catch { return false; }
    }

    private static string? GetArg(string[] args, string name)
    {
        for (int i = 0; i < args.Length - 1; i++)
        {
            if (string.Equals(args[i], name, StringComparison.OrdinalIgnoreCase))
                return args[i + 1];
        }
        return null;
    }

    private static string EscapeQuotes(string s) => s.Replace("\"", "\\\"");
}

internal static class GitRunner
{
    public static bool IsGitAvailable(out string version)
    {
        try
        {
            var p = Start("--version", Directory.GetCurrentDirectory(), token: null, capture: true);
            p.WaitForExit(4000);
            version = p.StandardOutput.ReadToEnd().Trim();
            return p.ExitCode == 0 && version.Contains("git version", StringComparison.OrdinalIgnoreCase);
        }
        catch
        {
            version = string.Empty;
            return false;
        }
    }

    public static async Task<int> Run(string workDir, string? token, string args)
    {
        var p = Start(args, workDir, token, capture: false);
        p.OutputDataReceived += (_, __) => { };
        p.ErrorDataReceived += (_, __) => { };
        p.BeginOutputReadLine();
        p.BeginErrorReadLine();
        await Task.Run(() => p.WaitForExit());
        return p.ExitCode;
    }

    public static async Task<(string StdOut, string StdErr, int Code)> RunCapture(string workDir, string? token, string args)
    {
        var p = Start(args, workDir, token, capture: true);
        var stdOut = new StringBuilder();
        var stdErr = new StringBuilder();
        p.OutputDataReceived += (_, e) => { if (e.Data != null) stdOut.AppendLine(e.Data); };
        p.ErrorDataReceived += (_, e) => { if (e.Data != null) stdErr.AppendLine(e.Data); };
        p.BeginOutputReadLine();
        p.BeginErrorReadLine();
        await Task.Run(() => p.WaitForExit());
        return (stdOut.ToString(), stdErr.ToString(), p.ExitCode);
    }

    private static Process Start(string args, string workDir, string? token, bool capture)
    {
        var psi = new ProcessStartInfo("git")
        {
            WorkingDirectory = workDir,
            UseShellExecute = false,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            CreateNoWindow = true
        };

        // Durcissement sécurité: pas de prompts interactifs, pas de stockage de credentials
        psi.Environment["GIT_TERMINAL_PROMPT"] = "0";
        psi.Environment["GCM_INTERACTIVE"] = "Never";

        // Always set the requested git arguments
        psi.Arguments = args ?? string.Empty;

        if (!string.IsNullOrEmpty(token))
        {
            // Inject Authorization header via -c for this single git invocation, avoid persisting credentials
            var basic = Convert.ToBase64String(Encoding.UTF8.GetBytes($"x-access-token:{token}"));
            var header = $"-c \"http.extraHeader=Authorization: Basic {basic}\"";
            psi.Arguments = string.IsNullOrWhiteSpace(psi.Arguments) ? header : $"{header} {psi.Arguments}";
        }

        return Process.Start(psi)!;
    }
}

internal static class TokenProvider
{
    public static string? TryGetToken()
    {
        // 1) Env var
        var env = Environment.GetEnvironmentVariable("GITHUB_TOKEN");
        if (!string.IsNullOrWhiteSpace(env)) return env;

        // 2) DPAPI-protected file under %APPDATA%\AutoBackupAgent\token.bin
        try
        {
            if (!OperatingSystem.IsWindows()) return null;
            var dir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "AutoBackupAgent");
            var file = Path.Combine(dir, "token.bin");
            if (!File.Exists(file)) return null;
            var protectedBytes = File.ReadAllBytes(file);
            var bytes = System.Security.Cryptography.ProtectedData.Unprotect(protectedBytes, null, System.Security.Cryptography.DataProtectionScope.CurrentUser);
            return Encoding.UTF8.GetString(bytes);
        }
        catch
        {
            return null;
        }
    }
}
internal static class SecretGuard
{
    private static readonly string[] SensitivePaths = new[]
    {
        "gcp-key.json",
        "kafka_certs",
        "oracle-driver",
        "*.pem",
        "*.key",
        "*.pfx",
        "*.cer",
        "*.cert",
        "*.jks",
        "*.keystore",
        "*.der",
        ".env",
        ".env.*",
        "appsettings.*.secrets.json"
    };

    public static async Task<string?> CheckForSecretsAsync(string root, string? token)
    {
        // 1) patterns explicites (fichiers présents ET non ignorés)
        var hits = new List<string>();

        foreach (var pattern in SensitivePaths)
        {
            // gérer simples patterns glob basiques
            IEnumerable<string> candidates = Enumerable.Empty<string>();
            if (pattern.Contains('*'))
            {
                var files = Directory.EnumerateFiles(root, pattern, SearchOption.AllDirectories);
                candidates = files;
            }
            else
            {
                var path = Path.Combine(root, pattern);
                if (File.Exists(path)) candidates = new[] { path };
                if (Directory.Exists(path)) candidates = candidates.Concat(Directory.EnumerateFileSystemEntries(path, "*", SearchOption.AllDirectories));
            }

            foreach (var file in candidates)
            {
                var rel = Path.GetRelativePath(root, file);
                // vérifier si ignoré
                var res = await GitRunner.RunCapture(root, token, $"check-ignore \"{rel}\"");
                if (res.Code == 0)
                    continue; // ignoré

                hits.Add(rel);
            }
        }

        if (hits.Count > 0)
        {
            return $"Des fichiers sensibles non ignorés ont été détectés: {string.Join(", ", hits.Take(10))}{(hits.Count>10?", ...":"")}";
        }

        return null;
    }
}
