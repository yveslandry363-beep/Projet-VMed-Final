# Fichier: scout_service.py
# Description: Service qui scanne les nouvelles recherches médicales et met à jour la base de connaissances RAG.

import feedparser
import time
import requests
from ingest import main as run_ingestion # Réutilise le script d'ingestion de la Phase 2

# --- CONFIGURATION ---
SOURCES = {
    "PubMed": "https://pubmed.ncbi.nlm.nih.gov/rss/search/1N1Ie2O2p8o8_g-yS2O6o-yS2O6o-yS2O6o-yS2O6/?limit=15&utm_campaign=pubmed-2&fc=20251107030808",
    "WHO": "https://www.who.int/rss-feeds/news-rss.xml",
    "arXiv_Biology": "http://export.arxiv.org/rss/q-bio"
}
GEMINI_VALIDATION_ENDPOINT = "http://gemini-consumer-app:8080/validate-source" # Endpoint exposé par l'app C#

def fetch_new_articles():
    """Scanne le flux RSS de PubMed pour de nouveaux articles."""
    print("🛰️  ScoutService: Recherche de nouvelles publications sur plusieurs sources...")
    all_entries = []
    for source_name, url in SOURCES.items():
        print(f"   -> Scan de {source_name}...")
        feed = feedparser.parse(url)
        all_entries.extend(feed.entries)
    
    new_articles_found = 0
    for entry in all_entries:
        print(f"  - Article trouvé: {entry.title}")
        
        # --- AMÉLIORATION "JAMAIS VUE": BOUCLE DE VALIDATION COGNITIVE ---
        if is_article_credible(entry.title, entry.summary):
            print("     ✅ Article jugé crédible par l'IA. Sauvegarde pour ingestion.")
            save_article_as_pdf(entry.title, entry.summary)
            new_articles_found += 1
        else:
            print("     ❌ Article jugé non pertinent ou non crédible. Ignoré.")
        
    print(f"✅ {new_articles_found} nouveaux articles potentiels identifiés.")
    return new_articles_found > 0

def save_article_as_pdf(title, content):
    """Simule la sauvegarde d'un article en PDF."""
    # Cette fonction est une simulation. Un vrai projet nécessiterait
    # une logique complexe pour scraper et convertir en PDF.
    file_path = f"recherche_medicale/{title.replace(' ', '_').replace(':', '')[:50]}.txt"
    with open(file_path, "w", encoding="utf-8") as f:
        f.write(f"Title: {title}\n\n{content}")

def is_article_credible(title, summary):
    """Utilise l'IA elle-même pour valider la crédibilité d'un article."""
    try:
        payload = {"title": title, "summary": summary}
        response = requests.post(GEMINI_VALIDATION_ENDPOINT, json=payload, timeout=60)
        response.raise_for_status()
        result = response.json()
        # On s'attend à ce que l'API retourne un simple booléen
        return result.get("isCredible", False)
    except requests.exceptions.RequestException as e:
        print(f"   [WARN] Impossible de contacter le service de validation: {e}")
        # En cas d'échec, on est conservateur et on refuse l'article.
        return False

def main():
    """Boucle principale du ScoutService."""
    print("🤖 Démarrage du ScoutService (Chercheur Autonome)...")
    while True:
        has_new_articles = fetch_new_articles()
        
        if has_new_articles:
            print("📚 De nouveaux articles ont été trouvés. Mise à jour de la base de connaissances RAG...")
            # On appelle directement la fonction main de notre script d'ingestion de la Phase 2
            run_ingestion()
            print("✅ Base de connaissances mise à jour avec les dernières recherches.")
        else:
            print("👍 Aucune nouvelle publication pertinente trouvée.")
            
        print("😴 Attente de 24 heures avant la prochaine recherche...")
        time.sleep(86400) # Attend 24 heures

if __name__ == "__main__":
    main()