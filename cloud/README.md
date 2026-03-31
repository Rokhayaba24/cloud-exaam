# 🏥 MediScan Africa — Projet P-10
## Plateforme Intelligente de Détection de Maladies
**AWS Cloud Foundations — ISI Dakar 2025-2026**

---

## Structure du projet

```
mediscan_aws/
├── scripts/
│   ├── 01_deploy_infrastructure.sh  ← VPC, SG, S3, IAM, DynamoDB
│   ├── 02_deploy_ec2.sh             ← Instance EC2 + User Data
│   ├── 03_deploy_rds.sh             ← RDS MySQL
│   └── 05_setup_cloudwatch.sh       ← Alarmes + Dashboard
├── api/
│   └── app.py                       ← API Flask (déployer sur EC2)
├── lambda/
│   └── lambda_inference.py          ← Lambda inférence + rotation modèles
├── sql/
│   └── init_database.sql            ← Schéma + données fictives
└── README.md
```

## Prérequis

```bash
# 1. AWS CLI installé et configuré
aws configure
# → AWS Access Key ID
# → AWS Secret Access Key
# → Region : eu-west-1 (ou us-east-1 pour Free Tier)

# 2. Python 3.10+
# 3. Les modèles .pkl générés depuis le notebook ML
```

---

## Déploiement étape par étape

### Étape 1 — Infrastructure de base
```bash
chmod +x scripts/*.sh
bash scripts/01_deploy_infrastructure.sh
```
Crée : VPC, sous-réseaux, IGW, Security Groups, S3, IAM, DynamoDB

### Étape 2 — Serveur EC2
```bash
bash scripts/02_deploy_ec2.sh
```
Lance : instance t2.micro Amazon Linux 2023, attache le rôle IAM

### Étape 3 — Base de données
```bash
bash scripts/03_deploy_rds.sh
# Attendre ~5-10 min que le status soit "available"
aws rds describe-db-instances --db-instance-identifier mediscan-africa-mysql \
    --query 'DBInstances[0].DBInstanceStatus'
```

### Étape 4 — Upload des modèles ML
```bash
source /tmp/mediscan_infra_ids.env

# Uploader les modèles générés par le notebook
aws s3 cp models/model_diabete_v1.0_*.pkl \
    s3://$BUCKET_NAME/models/diabete/v1.0/model_diabete_v1.0.pkl

aws s3 cp models/model_cancer_v1.0_*.pkl \
    s3://$BUCKET_NAME/models/cancer/v1.0/model_cancer_v1.0.pkl
```

### Étape 5 — Déploiement de l'API
```bash
source /tmp/mediscan_infra_ids.env

# Copier l'API sur EC2
scp -i ~/.ssh/mediscan-africa-keypair.pem \
    api/app.py \
    ec2-user@$PUBLIC_IP:/opt/mediscan/

# Initialiser la base de données
scp -i ~/.ssh/mediscan-africa-keypair.pem \
    sql/init_database.sql \
    ec2-user@$PUBLIC_IP:/tmp/

# Se connecter et lancer l'API
ssh -i ~/.ssh/mediscan-africa-keypair.pem ec2-user@$PUBLIC_IP

# Sur EC2 :
pip3.11 install flask boto3 scikit-learn pandas numpy joblib pymysql gunicorn
export S3_BUCKET="votre-bucket"
export RDS_ENDPOINT="votre-endpoint.rds.amazonaws.com"
export DB_PASSWORD="MediScan2025!Secure"
cd /opt/mediscan && python app.py
```

### Étape 6 — CloudWatch
```bash
bash scripts/05_setup_cloudwatch.sh
```

---

## Tests de l'API

```bash
# Health check
curl http://$PUBLIC_IP:5000/health

# Test Scénario A — Diabète
curl -X POST http://$PUBLIC_IP:5000/diagnostic \
  -H "Content-Type: application/json" \
  -d '{
    "scenario": "A_diabete",
    "patient_id": 1,
    "features": {
      "grossesses": 3,
      "glucose": 148,
      "pression_arterielle": 72,
      "epaisseur_pli": 35,
      "insuline": 0,
      "imc": 33.6,
      "pedigree_diabete": 0.627,
      "age": 50
    }
  }'

# Test Scénario B — Cancer
curl -X POST http://$PUBLIC_IP:5000/diagnostic \
  -H "Content-Type: application/json" \
  -d '{
    "scenario": "B_cancer",
    "features": {
      "mean radius": 17.99,
      "mean texture": 10.38,
      "mean perimeter": 122.8,
      "mean area": 1001.0,
      "mean smoothness": 0.1184,
      "mean compactness": 0.2776,
      "mean concavity": 0.3001,
      "mean concave points": 0.1471,
      "mean symmetry": 0.2419,
      "mean fractal dimension": 0.07871,
      "worst radius": 25.38,
      "worst texture": 17.33,
      "worst perimeter": 184.6,
      "worst area": 2019.0,
      "worst smoothness": 0.1622,
      "worst compactness": 0.6656,
      "worst concavity": 0.7119,
      "worst concave points": 0.2654,
      "worst symmetry": 0.4601,
      "worst fractal dimension": 0.1189
    }
  }'

# Historique patient
curl http://$PUBLIC_IP:5000/patient/1/historique

# Statistiques agrégées
curl http://$PUBLIC_IP:5000/stats/aggregees
```

---

## Services AWS mobilisés (référence modules)

| Module | Service | Usage |
|--------|---------|-------|
| M4 | IAM Roles | EC2Role, LambdaRole (least-privilege) |
| M5 | VPC, SG | 2 sous-réseaux, 2 Security Groups |
| M6 | EC2, Lambda | API Flask + inférence ML |
| M7 | S3 | Modèles ML versionnés, reports |
| M8 | RDS MySQL, DynamoDB | Patients fictifs + cache TTL |
| M9 | Well-Architected | Sécurité + Fiabilité |
| M10 | CloudWatch | 5 alarmes + dashboard |

---

## Coûts estimés (AWS Free Tier)

| Service | Free Tier | Usage projet |
|---------|-----------|-------------|
| EC2 t2.micro | 750h/mois | ~720h/mois |
| RDS db.t3.micro | 750h/mois | ~720h/mois |
| S3 | 5 GB | ~0.5 GB |
| Lambda | 1M req/mois | ~10K req |
| DynamoDB | 25 GB | ~0.1 GB |
| **Total estimé** | | **~0 USD (Free Tier)** |

> ⚠️ Penser à arrêter EC2 et RDS quand non utilisé pour préserver les crédits Academy.

---

## ⚠️ Note éthique

Ce projet est un exercice académique dans le cadre du cours AWS Cloud Foundations.
Les modèles ML sont entraînés sur des datasets publics à des fins pédagogiques.
**Ils ne doivent en aucun cas être utilisés dans un contexte médical réel.**

---

*Projet P-10 — AWS Cloud Foundations — ISI Dakar — A.A. 2025-2026*
