# Fichier: cognitive_archive_service.py
# Description: Écoute les événements système et maintient une archive immuable de l'évolution de l'IA.

import json
from kafka import KafkaConsumer
from datetime import datetime

# --- CONFIGURATION ---
KAFKA_BOOTSTRAP_SERVERS = 'kafka:9092' # Adresse interne Docker
EVENTS_TOPIC = 'system_events'
ARCHIVE_FILE = '/archive/cognitive_archive.md'

def write_to_archive(event_data):
    """Écrit un événement formaté dans le fichier d'archive."""
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    event_type = event_data.get('type', 'INCONNU').upper()
    service = event_data.get('service', 'N/A')
    message = event_data.get('message', '')
    details = event_data.get('details', {})

    with open(ARCHIVE_FILE, 'a', encoding='utf-8') as f:
        f.write(f"## {event_type} - {timestamp}\n\n")
        f.write(f"- **Service Concerné:** `{service}`\n")
        f.write(f"- **Événement:** {message}\n")
        
        if 'version' in details:
            f.write(f"- **Nouvelle Version:** `{details['version']}`\n")
        if 'solution' in details:
            f.write(f"- **Solution Appliquée:** {details['solution']}\n")
        if 'error' in details:
            f.write(f"- **Erreur Détaillée:** ```\n{details['error']}\n```\n")
            
        f.write("\n---\n\n")

def main():
    """Point d'entrée du service d'archivage."""
    print("📖 Démarrage du Cognitive Archive Service...")
    
    consumer = KafkaConsumer(
        EVENTS_TOPIC,
        bootstrap_servers=KAFKA_BOOTSTRAP_SERVERS,
        auto_offset_reset='earliest',
        group_id='cognitive-archive-group',
        value_deserializer=lambda v: json.loads(v.decode('utf-8'))
    )

    print(f"✅ Abonné au topic d'événements '{EVENTS_TOPIC}'. En attente d'événements...")

    for message in consumer:
        event_data = message.value
        print(f"✍️ Nouvel événement reçu: {event_data.get('type')}")
        write_to_archive(event_data)

if __name__ == "__main__":
    main()