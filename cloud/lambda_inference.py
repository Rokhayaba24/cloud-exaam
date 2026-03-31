"""
MediScan Africa — Lambda d'inférence ML (Projet P-10)
Déclenchée par l'API Flask OU directement sur S3 PUT

Configuration Lambda AWS :
  - Runtime    : Python 3.12
  - Mémoire    : 512 MB
  - Timeout    : 30 secondes
  - IAM Role   : mediscan-africa-lambda-role
"""

import os
import json
import time
import boto3
import joblib
import logging
import numpy as np
import pandas as pd
from datetime import datetime, timezone

logger = logging.getLogger()
logger.setLevel(logging.INFO)

S3_BUCKET    = os.environ.get('S3_BUCKET', 'mediscan-africa')
AWS_REGION   = os.environ.get('AWS_DEFAULT_REGION', 'eu-west-1')
DYNAMO_TABLE = 'mediscan-cache-diagnostics'

s3       = boto3.client('s3', region_name=AWS_REGION)
dynamodb = boto3.resource('dynamodb', region_name=AWS_REGION)

# Cache en mémoire entre les invocations chaudes (warm start)
_model_cache = {}


def load_model(scenario: str, version: str = 'v1.0'):
    """Charge le modèle depuis S3, mis en cache dans /tmp (warm Lambda)"""
    cache_key = f"{scenario}#{version}"
    if cache_key in _model_cache:
        return _model_cache[cache_key]

    s3_key   = f"models/{scenario}/{version}/model_{scenario}_{version}.pkl"
    tmp_path = f"/tmp/model_{scenario}_{version}.pkl"

    if not os.path.exists(tmp_path):
        logger.info(f"Téléchargement S3: {s3_key}")
        s3.download_file(S3_BUCKET, s3_key, tmp_path)

    model = joblib.load(tmp_path)
    _model_cache[cache_key] = model
    logger.info(f"Modèle {cache_key} chargé")
    return model


def predict(scenario: str, features: dict, version: str = 'v1.0') -> dict:
    """Effectue la prédiction et retourne le résultat structuré"""
    start = time.time()
    model = load_model(scenario, version)

    if scenario == 'A_diabete':
        glucose = features.get('glucose', 0)
        imc     = features.get('imc', 0)
        age     = features.get('age', 0)
        grossesses = features.get('grossesses', 0)
        features_enriched = dict(features)
        features_enriched['glucose_imc']    = glucose * imc
        features_enriched['age_grossesses'] = age * grossesses
        features_enriched['obese']          = int(imc >= 30)
        features_enriched['hyperglycemie']  = int(glucose >= 140)
        features_enriched['senior']         = int(age >= 45)

        col_order = ['grossesses', 'glucose', 'pression_arterielle',
                     'epaisseur_pli', 'insuline', 'imc', 'pedigree_diabete', 'age',
                     'glucose_imc', 'age_grossesses', 'obese', 'hyperglycemie', 'senior']
        row = {c: features_enriched.get(c, 0) for c in col_order}

    else:
        col_order = [
            'mean radius', 'mean texture', 'mean perimeter', 'mean area',
            'mean smoothness', 'mean compactness', 'mean concavity',
            'mean concave points', 'mean symmetry', 'mean fractal dimension',
            'radius error', 'texture error', 'perimeter error', 'area error',
            'smoothness error', 'compactness error', 'concavity error',
            'concave points error', 'symmetry error', 'fractal dimension error',
            'worst radius', 'worst texture', 'worst perimeter', 'worst area',
            'worst smoothness', 'worst compactness', 'worst concavity',
            'worst concave points', 'worst symmetry', 'worst fractal dimension'
        ]
        row = {c: features.get(c, 0) for c in col_order}

    df = pd.DataFrame([row])
    proba = float(model.predict_proba(df)[0][1])
    latency_ms = (time.time() - start) * 1000

    return {
        'probabilite':  round(proba, 4),
        'score_risque': round(proba * 1000, 1),
        'latency_ms':   round(latency_ms, 2),
        'model_version': version,
        'timestamp':    datetime.now(timezone.utc).isoformat()
    }


def handler(event, context):
    """
    Handler principal Lambda.
    Deux modes d'invocation :
    1. Via invoke direct (depuis l'API Flask)
    2. Via API Gateway (future évolution)
    """
    logger.info(f"Event: {json.dumps(event)[:500]}")

    # Extraction des paramètres
    body = event
    if 'body' in event:
        body = json.loads(event['body']) if isinstance(event['body'], str) else event['body']

    scenario = body.get('scenario')
    features = body.get('features', {})

    if not scenario or not features:
        return {
            'statusCode': 400,
            'body': json.dumps({'error': 'scenario et features requis'})
        }

    if scenario not in ('A_diabete', 'B_cancer'):
        return {
            'statusCode': 400,
            'body': json.dumps({'error': 'scenario invalide'})
        }

    try:
        result = predict(scenario, features)
        return {
            'statusCode': 200,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps(result)
        }
    except Exception as e:
        logger.error(f"Erreur Lambda: {e}", exc_info=True)
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }


# ─────────────────────────────────────────────────────────────────────────────
# LAMBDA DE ROTATION DES MODÈLES
# Fichier séparé à déployer comme deuxième fonction Lambda
# Déclencheur : S3 PUT sur s3://mediscan-africa/models/*/new/
# ─────────────────────────────────────────────────────────────────────────────

def rotation_handler(event, context):
    """
    Lambda déclenchée quand un nouveau modèle arrive dans S3.
    Elle copie le nouveau modèle vers /latest/ (modèle actif).

    Déclencheur S3 : PUT sur models/*/new/*.pkl
    """
    logger.info("Lambda rotation modèle déclenchée")

    for record in event.get('Records', []):
        s3_event = record.get('s3', {})
        bucket   = s3_event.get('bucket', {}).get('name')
        key      = s3_event.get('object', {}).get('key', '')

        # Exemple de clé : models/diabete/new/model_diabete_v2.0.pkl
        parts = key.split('/')
        if len(parts) < 4 or parts[2] != 'new':
            logger.warning(f"Clé S3 inattendue ignorée: {key}")
            continue

        scenario      = parts[1]            # diabete ou cancer
        filename      = parts[-1]           # model_diabete_v2.0.pkl
        latest_key    = f"models/{scenario}/latest/{filename}"

        # Copier vers /latest/ (remplace l'ancien)
        s3.copy_object(
            Bucket=bucket,
            CopySource={'Bucket': bucket, 'Key': key},
            Key=latest_key
        )

        logger.info(f"Modèle {scenario} mis à jour: {key} → {latest_key}")

        # Vider le cache Lambda (forcer rechargement)
        cache_key = f"{scenario}#latest"
        if cache_key in _model_cache:
            del _model_cache[cache_key]
            tmp_path = f"/tmp/model_{scenario}_latest.pkl"
            if os.path.exists(tmp_path):
                os.remove(tmp_path)
            logger.info(f"Cache Lambda vidé pour {scenario}")

    return {'statusCode': 200, 'body': 'Rotation modèle terminée'}
