# Fichier: knowledge_ingester_service.py
# Description: Consomme les articles validés depuis Kafka et les ingère dans Milvus par lots optimisés.

import json
import time
import os
from kafka import KafkaConsumer
from ingest import main as run_ingestion

# --- CONFIGURATION ---
KAFKA_BOOTSTRAP_SERVERS = 'kafka:9092'
INGESTION_TOPIC = 'knowledge_ingestion_queue'
INGESTION_DIR = "recherche_medicale"
BATCH_SIZE = 100  # Nombre d'articles à accumuler avant d'ingérer
BATCH_TIMEOUT_SECONDS = 300 # Ou ingérer toutes les 5 minutes

def main():
    """Boucle principale du service d'ingestion."""
    print("📚 Démarrage du Knowledge Ingester Service...")
    
    consumer = KafkaConsumer(
        INGESTION_TOPIC,
        bootstrap_servers=KAFKA_BOOTSTRAP_SERVERS,
        auto_offset_reset='earliest',
        group_id='knowledge-ingester-group',
        value_deserializer=lambda v: json.loads(v.decode('utf-8'))
    )

    article_buffer = []
    last_ingestion_time = time.time()

    while True:
        # Consommer les messages avec un timeout pour ne pas bloquer indéfiniment
        messages = consumer.poll(timeout_ms=1000, max_records=BATCH_SIZE)
        
        for topic_partition, records in messages.items():
            for record in records:
                article_data = record.value
                print(f"  -> Reçu article '{article_data['title'][:40]}...' pour ingestion.")
                
                # Sauvegarder l'article dans le dossier d'ingestion
                file_path = f"{INGESTION_DIR}/{article_data['title'].replace(' ', '_').replace(':', '')[:50]}.txt"
                with open(file_path, "w", encoding="utf-8") as f:
                    f.write(f"Title: {article_data['title']}\n\n{article_data['content']}")
                
                article_buffer.append(article_data)

        # Déclencher l'ingestion si le buffer est plein ou si le timeout est atteint
        if len(article_buffer) >= BATCH_SIZE or (time.time() - last_ingestion_time > BATCH_TIMEOUT_SECONDS and article_buffer):
            print(f"🔥 Seuil atteint ({len(article_buffer)} articles). Lancement de l'ingestion par lot dans Milvus...")
            run_ingestion()
            print("✅ Ingestion par lot terminée. Nettoyage du buffer et des fichiers.")
            article_buffer.clear()
            # Nettoyer les fichiers traités du dossier
            for filename in os.listdir(INGESTION_DIR):
                os.remove(os.path.join(INGESTION_DIR, filename))
            last_ingestion_time = time.time()

if __name__ == "__main__":
    main()