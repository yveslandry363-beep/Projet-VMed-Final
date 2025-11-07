# Fichier: meta_cognitive_prompter.py
# Description: Reçoit des objectifs, génère des prompts intelligents pour Gemini,
#              et archive les solutions proposées.

import os
import json
from kafka import KafkaConsumer, KafkaProducer
import google.generativeai as genai

# --- CONFIGURATION ---
KAFKA_BOOTSTRAP_SERVERS = 'kafka:9092'
META_PROMPT_TOPIC = 'meta_cognitive_prompts'
EVENTS_TOPIC = 'system_events'

# IMPORTANT: Ce service utilisera la clé API Gemini standard (gratuite ou payante)
# car il est découplé de l'application C# qui utilise Vertex AI.
GOOGLE_API_KEY = os.environ.get('GEMINI_API_KEY')

def main():
    """Boucle principale du Meta-Prompter."""
    if not GOOGLE_API_KEY:
        print("❌ [META_PROMPTER] ERREUR: La variable d'environnement GEMINI_API_KEY n'est pas définie. Ce service ne peut pas fonctionner.")
        return

    print("🤖 Démarrage du Meta-Cognitive Prompter...")
    genai.configure(api_key=GOOGLE_API_KEY)
    model = genai.GenerativeModel('gemini-1.5-pro-latest') # Utilise le meilleur modèle disponible via l'API Key

    consumer = KafkaConsumer(
        META_PROMPT_TOPIC,
        bootstrap_servers=KAFKA_BOOTSTRAP_SERVERS,
        auto_offset_reset='earliest',
        group_id='meta-prompter-group',
        value_deserializer=lambda v: json.loads(v.decode('utf-8'))
    )
    
    producer = KafkaProducer(
        bootstrap_servers=KAFKA_BOOTSTRAP_SERVERS,
        value_serializer=lambda v: json.dumps(v).encode('utf-8')
    )

    print("✅ Prêt à recevoir des objectifs du Superviseur.")

    for message in consumer:
        goal_data = message.value
        goal_id = goal_data.get('goal_id')
        prompt = goal_data.get('prompt_for_gemini')

        print(f"🧠 [META_PROMPTER] Nouvel objectif reçu ({goal_id}). Interrogation de Gemini Pro...")
        
        try:
            # Pose la question à Gemini
            response = model.generate_content(prompt)
            solution_text = response.text

            print(f"✅ [META_PROMPTER] Solution reçue de Gemini. Archivage...")

            # Archive la solution
            archive_event = {'type': 'SOLUTION_PROPOSEE', 'service': 'MetaCognitivePrompter', 'message': f"Solution proposée par l'IA pour l'objectif {goal_id}.", 'details': {'goal': prompt, 'solution': solution_text}}
            producer.send(EVENTS_TOPIC, value=archive_event)
            producer.flush()

        except Exception as e:
            print(f"❌ [META_PROMPTER] Erreur lors de l'appel à l'API Gemini: {e}")

if __name__ == "__main__":
    main()