# Fichier: query_knowledge.py
# Description: Script interactif pour interroger la base de connaissances Milvus.

import os
from dotenv import load_dotenv
from langchain_google_genai import GoogleGenerativeAIEmbeddings
from langchain_community.vectorstores import Milvus

load_dotenv()

# --- CONFIGURATION ---
MILVUS_HOST = "localhost"
MILVUS_PORT = "19530"
COLLECTION_NAME = "medical_knowledge_base"

def main():
    """
    Lance une session interactive pour interroger la base de connaissances.
    """
    print("🧠 Initialisation de l'interface de requête de la base de connaissances...")
    
    try:
        # Utilise le même modèle d'embedding que pour l'ingestion
        embeddings = GoogleGenerativeAIEmbeddings(model="models/text-embedding-004")

        # Se connecte à la base de données vectorielle existante
        vector_store = Milvus(
            embedding_function=embeddings,
            collection_name=COLLECTION_NAME,
            connection_args={"host": MILVUS_HOST, "port": MILVUS_PORT},
        )
        print("✅ Connecté à la base de connaissances Milvus.")
        print("❓ Posez une question (ex: 'Quels sont les traitements pour le diabète de type 2 ?') ou tapez 'quitter'.")

    except Exception as e:
        print(f"❌ ERREUR: Impossible de se connecter à Milvus: {e}")
        print("   Assurez-vous que la stack Docker est démarrée et que le service `scout_service.py` a déjà tourné au moins une fois.")
        return

    # Boucle de requête interactive
    while True:
        query = input("\nVotre question > ")
        if query.lower() in ['quitter', 'exit', 'q']:
            break
        
        print("   Recherche des documents similaires...")
        # Fait une recherche de similarité dans Milvus
        similar_docs = vector_store.similarity_search(query, k=3) # Trouve les 3 morceaux les plus pertinents
        
        print("\n--- RÉSULTATS TROUVÉS DANS LA BASE DE CONNAISSANCES ---")
        for i, doc in enumerate(similar_docs):
            print(f"\n📄 Document {i+1} (Source: {doc.metadata.get('source', 'N/A')})")
            print("-" * 20)
            print(doc.page_content)
        print("\n" + "="*60)

    print("👋 Session terminée.")

if __name__ == "__main__":
    main()