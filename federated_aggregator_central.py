# Fichier: federated_aggregator_central.py
# Description: Service central qui reçoit les mises à jour de poids de tous les hôpitaux
#              et les agrège pour améliorer le modèle global.

from flask import Flask, request, jsonify
import torch

app = Flask(__name__)

# --- Stockage en mémoire (pour la démo) ---
# Dans un vrai projet, on utiliserait une base de données ou un stockage de fichiers.
global_model_weights = None
received_weights_buffer = []

@app.route('/submit_weights', methods=['POST'])
def submit_weights():
    """Point d'entrée pour recevoir les poids des hôpitaux Edge."""
    data = request.get_json()
    hospital_id = data.get('hospital_id')
    weights_data = data.get('weights_data') # Les poids sérialisés
    
    print(f"📦 Poids reçus de l'hôpital: {hospital_id}")
    
    # Désérialiser et stocker les poids
    # ... logique de désérialisation ...
    received_weights_buffer.append(weights_data)
    
    # Si on a reçu assez de mises à jour, on lance l'agrégation
    if len(received_weights_buffer) >= 3: # Ex: agréger après 3 mises à jour
        aggregate_weights()
        
    return jsonify({"status": "received"}), 200

def aggregate_weights():
    """Agrège les poids reçus pour mettre à jour le modèle global."""
    print("🔄 Agrégation des poids pour créer une nouvelle version du modèle global...")
    
    # Algorithme d'agrégation (ex: Federated Averaging - FedAvg)
    # 1. Charger le modèle global actuel.
    # 2. Calculer la moyenne des poids reçus de chaque hôpital.
    # 3. Appliquer cette moyenne au modèle global.
    # 4. Sauvegarder le nouveau modèle global.
    
    print("✅ Nouveau modèle global v1.2 créé !")
    received_weights_buffer.clear() # Vider le buffer

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=80)