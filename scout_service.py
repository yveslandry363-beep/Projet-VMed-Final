# Fichier: scout_service.py
# Description: Service qui scanne les nouvelles recherches médicales et met à jour la base de connaissances RAG.

import asyncio
import feedparser
import time
import httpx
import json
from kafka import KafkaProducer

# --- CONFIGURATION ---
SOURCES = {
    "PubMed": "https://pubmed.ncbi.nlm.nih.gov/rss/search/1N1Ie2O2p8o8_g-yS2O6o-yS2O6o-yS2O6o-yS2O6/?limit=15&utm_campaign=pubmed-2&fc=20251107030808",
    "WHO": "https://www.who.int/rss-feeds/news-rss.xml",
    "arXiv_Biology": "http://export.arxiv.org/rss/q-bio"
}
GEMINI_VALIDATION_ENDPOINT = "http://gemini-consumer-app:8080/validate-source" # Endpoint exposé par l'app C#
MAX_CONCURRENT_TASKS = 50 # Nombre de tâches parallèles (scan, validation)
KAFKA_BOOTSTRAP_SERVERS = 'kafka:9092'
INGESTION_TOPIC = 'knowledge_ingestion_queue'

async def fetch_source(session, source_name, url):
    """Scanne un seul flux RSS de manière asynchrone."""
    print(f"   -> Scan asynchrone de {source_name}...")
    try:
        response = await session.get(url, timeout=15)
        feed = feedparser.parse(response.text)
        return feed.entries
    except httpx.RequestError as e:
        print(f"   [WARN] Échec du scan de {source_name}: {e}")
        return []

async def fetch_all_articles_concurrently():
    """Scanne TOUTES les sources en parallèle."""
    print("🛰️  ScoutService: Recherche de nouvelles publications sur plusieurs sources...")
    async with httpx.AsyncClient() as session:
        tasks = [fetch_source(session, name, url) for name, url in SOURCES.items()]
        results = await asyncio.gather(*tasks)
        all_entries = [entry for feed_entries in results for entry in feed_entries]
    print(f"✅ {len(all_entries)} articles bruts trouvés sur toutes les sources.")
    return all_entries

async def validate_and_queue_article(session, producer, entry):
    """Utilise l'IA elle-même pour valider la crédibilité d'un article."""
    try:
        payload = {"title": entry.title, "summary": entry.summary}
        response = await session.post(GEMINI_VALIDATION_ENDPOINT, json=payload, timeout=60)
        response.raise_for_status()
        result = response.json()
        is_credible = result.get("isCredible", False)
        if is_credible:
            print(f"     ✅ Article '{entry.title[:30]}...' jugé crédible. Envoi vers la file d'ingestion.")
            article_data = {'title': entry.title, 'content': entry.summary, 'source': entry.link}
            producer.send(INGESTION_TOPIC, value=article_data)
        return is_credible
    except httpx.RequestError as e:
        print(f"   [WARN] Impossible de contacter le service de validation: {e}")
        # En cas d'échec, on est conservateur et on refuse l'article.
        return False

async def main():
    """Boucle principale du ScoutService."""
    print("🤖 Démarrage du ScoutService (Chercheur Autonome)...")
    producer = KafkaProducer(
        bootstrap_servers=KAFKA_BOOTSTRAP_SERVERS,
        value_serializer=lambda v: json.dumps(v).encode('utf-8')
    )

    while True:
        # --- AMÉLIORATION "JAMAIS VUE": EXÉCUTION MASSIVEMENT PARALLÈLE ---
        # 1. Scanner toutes les sources en même temps
        all_entries = await fetch_all_articles_concurrently()
        
        # 2. Valider tous les articles trouvés en parallèle
        print(f"🔬 Validation cognitive de {len(all_entries)} articles en parallèle (batchs de {MAX_CONCURRENT_TASKS})...")
        async with httpx.AsyncClient() as session:
            validation_tasks = [validate_and_queue_article(session, producer, entry) for entry in all_entries]
            for i in range(0, len(validation_tasks), MAX_CONCURRENT_TASKS):
                batch = validation_tasks[i:i+MAX_CONCURRENT_TASKS]
                await asyncio.gather(*batch)
        
        # Forcer l'envoi de tous les messages en attente dans le buffer du producer
        producer.flush()
        print("👍 Cycle de validation terminé. Les articles crédibles sont dans la file d'attente Kafka.")
            
        # --- AMÉLIORATION "JAMAIS VUE": RYTHME ADAPTATIF ---
        # Cycle rapide de 5 minutes pour une réactivité maximale sans surcharger les APIs.
        print("⏱️  Cycle d'enrichissement terminé. Prochain cycle dans 5 minutes.")
        await asyncio.sleep(300)

if __name__ == "__main__":
    asyncio.run(main())