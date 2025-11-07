# Fichier: ingest.py
# Description: Service d'ingestion pour la base de connaissances RAG.
#              Scanne les PDF, les découpe, les vectorise et les stocke dans Milvus.

import os
from dotenv import load_dotenv
from langchain_community.document_loaders import PyPDFDirectoryLoader
from langchain.text_splitter import RecursiveCharacterTextSplitter
from langchain_google_genai import GoogleGenerativeAIEmbeddings
from langchain_community.vectorstores import Milvus

load_dotenv()

# --- CONFIGURATION ---
PDF_SOURCE_DIR = "recherche_medicale"
MILVUS_HOST = "milvus" # Utilise le nom du service Docker
MILVUS_PORT = "19530"
COLLECTION_NAME = "medical_knowledge_base"

# Modèle d'embedding de Google (transforme le texte en vecteurs)
embeddings = GoogleGenerativeAIEmbeddings(model="models/text-embedding-004")

def main():
    """
    Point d'entrée du script d'ingestion.
    """
    print("🚀 Démarrage du service d'ingestion RAG...")

    # 1. Charger les documents PDF depuis le dossier
    print(f"📄 Étape 1/4: Chargement des documents depuis '{PDF_SOURCE_DIR}'...")
    if not os.path.exists(PDF_SOURCE_DIR) or not os.listdir(PDF_SOURCE_DIR):
        print(f"❌ ERREUR: Le dossier '{PDF_SOURCE_DIR}' est vide ou n'existe pas.")
        print("Veuillez y placer vos fichiers PDF de recherche médicale.")
        return

    loader = PyPDFDirectoryLoader(PDF_SOURCE_DIR)
    docs = loader.load()
    print(f"✅ {len(docs)} documents chargés.")

    # 2. Découper les documents en morceaux (chunks)
    print("🔪 Étape 2/4: Découpage des documents en morceaux (chunks)...")
    text_splitter = RecursiveCharacterTextSplitter(
        chunk_size=1000, 
        chunk_overlap=150
    )
    chunks = text_splitter.split_documents(docs)
    print(f"✅ {len(chunks)} morceaux de texte créés.")

    # 3. Vectoriser et stocker dans Milvus
    print("🧠 Étape 3/4: Vectorisation et stockage dans Milvus...")
    print(f"   (Connexion à Milvus sur {MILVUS_HOST}:{MILVUS_PORT})")
    
    try:
        # --- AMÉLIORATION "JAMAIS VUE": INGESTION PAR BATCHS ---
        # LangChain gère automatiquement l'envoi par batchs à l'API d'embedding,
        # ce qui est beaucoup plus rapide que d'envoyer les chunks un par un.
        vector_store = Milvus.from_documents(
            documents=chunks,
            embedding=embeddings,
            collection_name=COLLECTION_NAME,
            connection_args={"host": MILVUS_HOST, "port": MILVUS_PORT},
            batch_size=128 # Envoi de 128 chunks à la fois pour vectorisation
        )
        print("✅ Base de connaissances vectorielle créée/mise à jour avec succès.")
    except Exception as e:
        print(f"❌ ERREUR lors de la connexion ou de l'ingestion dans Milvus: {e}")
        print("   Assurez-vous que votre stack Docker (Milvus, etcd, MinIO) est bien démarrée.")
        return

    # 4. Vérification
    print("🔍 Étape 4/4: Vérification rapide...")
    try:
        retriever = vector_store.as_retriever(search_kwargs={'k': 1})
        test_query = "symptômes de la grippe"
        result = retriever.invoke(test_query)
        if result:
            print(f"✅ Test de recherche réussi. Un document similaire à '{test_query}' a été trouvé.")
            print("--- Extrait ---")
            print(result[0].page_content[:200] + "...")
            print("---------------")
        else:
            print("⚠️ Test de recherche n'a retourné aucun résultat.")
    except Exception as e:
        print(f"❌ ERREUR lors du test de recherche: {e}")

    print("\n🏁 Ingestion terminée.")

if __name__ == "__main__":
    main()