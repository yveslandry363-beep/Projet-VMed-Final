# Fichier: fine_tune_edge_model.py
# Description: Script pour fine-tuner un modèle léger (Gemma) pour le déploiement Edge.

import torch
from datasets import load_dataset
from transformers import (
    AutoModelForCausalLM,
    AutoTokenizer,
    BitsAndBytesConfig,
    TrainingArguments,
    Trainer,
)

# --- CONFIGURATION ---
MODEL_NAME = "google/gemma-2b" # Modèle léger et performant de Google
DATASET_PATH = "path/to/your/medical_dataset.csv" # CSV avec colonnes "diagnostic_text", "ia_guidance"
OUTPUT_DIR = "./results_edge_model"
FINE_TUNED_MODEL_DIR = "./fine_tuned_gemma_medical"

def main():
    print(f"🚀 Démarrage du fine-tuning du modèle Edge: {MODEL_NAME}")

    # 1. Charger le jeu de données (doit être au format question/réponse)
    print(f"💾 Chargement du jeu de données depuis {DATASET_PATH}...")
    # On formate le dataset pour l'entraînement
    def format_dataset(example):
        return {"text": f"### Diagnostic:\n{example['diagnostic_text']}\n\n### Recommandation:\n{example['ia_guidance']}"}

    dataset = load_dataset("csv", data_files=DATASET_PATH).map(format_dataset)
    print("✅ Jeu de données chargé et formaté.")

    # 2. Configuration de la quantification pour réduire l'usage mémoire (QLoRA)
    bnb_config = BitsAndBytesConfig(
        load_in_4bit=True,
        bnb_4bit_quant_type="nf4",
        bnb_4bit_compute_dtype=torch.bfloat16,
        bnb_4bit_use_double_quant=False,
    )

    # 3. Charger le modèle et le tokenizer
    print("🧠 Chargement du modèle de base et du tokenizer...")
    model = AutoModelForCausalLM.from_pretrained(
        MODEL_NAME,
        quantization_config=bnb_config,
        device_map="auto" # Utilise le GPU si disponible
    )
    tokenizer = AutoTokenizer.from_pretrained(MODEL_NAME, trust_remote_code=True)
    tokenizer.pad_token = tokenizer.eos_token
    print("✅ Modèle et tokenizer chargés.")

    # 4. Définir les arguments d'entraînement
    training_arguments = TrainingArguments(
        output_dir=OUTPUT_DIR,
        num_train_epochs=1, # 1 à 3 époques suffisent souvent pour le fine-tuning
        per_device_train_batch_size=4,
        gradient_accumulation_steps=1,
        learning_rate=2e-4,
        fp16=True,
        logging_steps=25,
    )

    # 5. Créer et lancer l'entraîneur
    print("🏃‍♂️ Démarrage de l'entraînement...")
    trainer = Trainer(
        model=model,
        train_dataset=dataset['train'],
        args=training_arguments,
        data_collator=lambda data: {'input_ids': torch.stack([f['input_ids'] for f in data]),
                                     'attention_mask': torch.stack([f['attention_mask'] for f in data]),
                                     'labels': torch.stack([f['input_ids'] for f in data])}
    )
    trainer.train()
    print("✅ Entraînement terminé.")

    # 6. Sauvegarder le modèle fine-tuné pour le déploiement Edge
    print(f"💾 Sauvegarde du modèle fine-tuné dans '{FINE_TUNED_MODEL_DIR}'...")
    trainer.save_model(FINE_TUNED_MODEL_DIR)
    print("🏁 Modèle Edge prêt à être déployé !")

if __name__ == "__main__":
    main()