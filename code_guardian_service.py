# Fichier: code_guardian_service.py
# Description: Surveille les changements de code, valide, et automatise les commits sur GitHub.

import time
import subprocess
from watchdog.observers import Observer
from watchdog.events import FileSystemEventHandler

# --- CONFIGURATION ---
PROJECT_PATH = "." # Surveille le dossier courant
GIT_REMOTE = "origin"
GIT_BRANCH = "main"
INACTIVITY_PERIOD_SECONDS = 300 # 5 minutes d'inactivité avant de déclencher

class ChangeHandler(FileSystemEventHandler):
    """Détecte les changements et gère le timer d'inactivité."""
    def __init__(self):
        self.last_modified = time.time()

    def on_any_event(self, event):
        # Ignorer les changements dans les dossiers de cache ou de build
        if "/bin/" in event.src_path or "/obj/" in event.src_path or ".git" in event.src_path:
            return
        
        print(f"   [GARDIEN] Changement détecté: {event.src_path}")
        self.last_modified = time.time()

def run_command(command):
    """Exécute une commande shell et retourne le succès et la sortie."""
    print(f"   [GARDIEN] Exécution: '{' '.join(command)}'")
    result = subprocess.run(command, capture_output=True, text=True, shell=True)
    if result.returncode != 0:
        print(f"   ❌ [GARDIEN] Échec de la commande. Erreur:\n{result.stderr}")
        return False, result.stderr
    return True, result.stdout

def main():
    """Boucle principale du Gardien du Code."""
    print("🛡️  Démarrage du Gardien Autonome du Code...")
    
    event_handler = ChangeHandler()
    observer = Observer()
    observer.schedule(event_handler, PROJECT_PATH, recursive=True)
    observer.start()

    print(f"✅ [GARDIEN] Surveillance du dossier '{PROJECT_PATH}' activée.")
    print(f"   Le Gardien agira après {INACTIVITY_PERIOD_SECONDS} secondes d'inactivité.")

    try:
        while True:
            time_since_last_change = time.time() - event_handler.last_modified
            
            if time_since_last_change > INACTIVITY_PERIOD_SECONDS:
                print("\n" + "="*50)
                print("⏳ [GARDIEN] Période d'inactivité détectée. Démarrage du cycle de sauvegarde.")
                
                # 1. Vérifier s'il y a des changements à commiter
                success, output = run_command(["git", "status", "--porcelain"])
                if not success or not output:
                    print("👍 [GARDIEN] Aucune modification détectée. Retour en mode surveillance.")
                    event_handler.last_modified = time.time() # Reset timer
                    time.sleep(60)
                    continue

                # 2. Valider la build locale
                print("   [GARDIEN] Validation de la build .NET...")
                build_success, _ = run_command(["dotnet", "build"])
                if not build_success:
                    print("   ❌ [GARDIEN] Build échouée. Le commit est annulé pour préserver l'intégrité de la branche.")
                    event_handler.last_modified = time.time() # Reset timer
                    continue
                
                # 3. Ajouter, Commiter et Pousser
                print("   [GARDIEN] Build réussie. Préparation du commit...")
                run_command(["git", "add", "."])
                
                commit_message = f"feat(auto): Sauvegarde autonome du {time.strftime('%Y-%m-%d %H:%M:%S')}"
                run_command(["git", "commit", "-m", commit_message])
                
                print("   [GARDIEN] Envoi des modifications vers GitHub...")
                push_success, _ = run_command(["git", "push", GIT_REMOTE, GIT_BRANCH])
                
                if push_success:
                    print("✅ [GARDIEN] Sauvegarde sur GitHub réussie. Retour en mode surveillance.")
                
                event_handler.last_modified = time.time() # Reset timer

            time.sleep(10)
    except KeyboardInterrupt:
        observer.stop()
    observer.join()
    print("\n🛡️  Gardien du Code arrêté.")

if __name__ == "__main__":
    main()