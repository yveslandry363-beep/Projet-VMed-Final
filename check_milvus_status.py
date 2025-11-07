# Fichier: check_milvus_status.py
# Description: Script pour interroger l'état de la base de données vectorielle Milvus.

from pymilvus import utility, connections

# --- CONFIGURATION ---
MILVUS_HOST = "localhost"
MILVUS_PORT = "19530"
COLLECTION_NAME = "medical_knowledge_base"

def main():
    """Se connecte à Milvus et affiche le statut de la collection de connaissances."""
    print(f"🔍 Interrogation de Milvus sur {MILVUS_HOST}:{MILVUS_PORT}...")
    
    try:
        # Se connecter à Milvus
        connections.connect("default", host=MILVUS_HOST, port=MILVUS_PORT)
        print("✅ Connexion à Milvus réussie.")

        # Vérifier si la collection existe
        if not utility.has_collection(COLLECTION_NAME):
            print(f"❌ La base de connaissances '{COLLECTION_NAME}' est VIDE.")
            print("   Raison: La collection n'a même pas encore été créée.")
            print("   💡 Lancez le script `scout_service.py` pour commencer à l'alimenter.")
            return

        # Obtenir les statistiques de la collection
        stats = utility.get_collection_stats(COLLECTION_NAME)
        entity_count = stats['row_count']

        print(f"✅ La base de connaissances '{COLLECTION_NAME}' existe.")
        print(f"🧠 Elle contient actuellement : {entity_count} morceaux de connaissance (vecteurs).")

    except Exception as e:
        print(f"❌ ERREUR: Impossible de se connecter à Milvus: {e}")
        print("   Assurez-vous que votre stack Docker est bien démarrée (`docker-compose up -d`).")

if __name__ == "__main__":
    main()