# Fichier: metrics_analyzer_service.py
# Description: Service AIOps qui prédit les pics de charge et pré-scale l'infrastructure K8s.

import os
import time
from datetime import datetime, timedelta
import numpy as np
from prometheus_api_client import PrometheusConnect
from sklearn.linear_model import LinearRegression
from kubernetes import client, config

# --- CONFIGURATION ---
PROMETHEUS_URL = "http://prometheus-service.monitoring.svc.cluster.local:9090"
KAFKA_LAG_QUERY = 'sum(kafka_consumergroup_lag{consumergroup="gemini-processor-group-RESET-3"}) by (consumergroup)'
TARGET_DEPLOYMENT = "gemini-consumer-deployment"
TARGET_SCALEDOBJECT = "gemini-consumer-scaler"
TARGET_NAMESPACE = "default"
PREDICTION_HORIZON_MINUTES = 60 # Prédire la charge pour la prochaine heure
PRE_SCALE_THRESHOLD = 100      # Si on prédit un lag > 100, on pré-scale
PRE_SCALE_REPLICAS = 10        # Nombre de répliques à démarrer en prévision du pic

def get_historical_data(prom):
    """Récupère les données historiques de lag Kafka depuis Prometheus."""
    print("📊 Récupération des données historiques de lag Kafka...")
    try:
        # Récupérer les données des 7 derniers jours, avec une résolution de 15 minutes
        result = prom.custom_query_range(
            query=KAFKA_LAG_QUERY,
            start_time=datetime.now() - timedelta(days=7),
            end_time=datetime.now(),
            step='15m'
        )
        if not result:
            return None
        
        # Formatter les données pour scikit-learn
        points = result[0]['values']
        timestamps = np.array([p[0] for p in points]).reshape(-1, 1)
        values = np.array([float(p[1]) for p in points])
        print(f"✅ {len(points)} points de données récupérés.")
        return timestamps, values
    except Exception as e:
        print(f"❌ Erreur lors de la récupération des données Prometheus: {e}")
        return None

def train_and_predict(timestamps, values):
    """Entraîne un modèle de régression simple et prédit le futur lag."""
    print("🧠 Entraînement du modèle de prédiction...")
    model = LinearRegression()
    model.fit(timestamps, values)
    
    # Prédire le lag dans PREDICTION_HORIZON_MINUTES
    future_timestamp = (datetime.now() + timedelta(minutes=PREDICTION_HORIZON_MINUTES)).timestamp()
    predicted_lag = model.predict(np.array([[future_timestamp]]))[0]
    
    print(f"🔮 Prédiction: Lag estimé dans {PREDICTION_HORIZON_MINUTES} min = {predicted_lag:.2f}")
    return predicted_lag

def pre_scale_deployment(replicas):
    """Met à jour le minReplicaCount de l'objet KEDA pour forcer un scaling prédictif."""
    print(f"🚀 Action AIOps: Pré-scaling à {replicas} répliques...")
    try:
        # Charger la configuration Kubernetes (fonctionne à l'intérieur d'un pod)
        config.load_incluster_config()
        api = client.CustomObjectsApi()
        
        # Patch pour mettre à jour minReplicaCount
        patch = {"spec": {"minReplicaCount": replicas}}
        
        api.patch_namespaced_custom_object(
            group="keda.sh",
            version="v1alpha1",
            name=TARGET_SCALEDOBJECT,
            namespace=TARGET_NAMESPACE,
            body=patch
        )
        print(f"✅ ScaledObject '{TARGET_SCALEDOBJECT}' mis à jour avec minReplicaCount = {replicas}.")
    except Exception as e:
        print(f"❌ Erreur lors de la mise à jour de KEDA via l'API K8s: {e}")

def main():
    print("🤖 Démarrage du service d'analyse de métriques AIOps...")
    prom = PrometheusConnect(url=PROMETHEUS_URL, disable_ssl=True)
    
    while True:
        data = get_historical_data(prom)
        if data:
            timestamps, values = data
            predicted_lag = train_and_predict(timestamps, values)
            
            if predicted_lag > PRE_SCALE_THRESHOLD:
                pre_scale_deployment(PRE_SCALE_REPLICAS)
            else:
                # S'assurer de revenir à la normale si le pic est passé
                print("📉 Aucune action requise. Le lag prédit est sous le seuil.")
                pre_scale_deployment(1) # Retour au minReplicaCount par défaut
        
        print(f"😴 Attente de 30 minutes avant la prochaine analyse...")
        time.sleep(1800)

if __name__ == "__main__":
    main()