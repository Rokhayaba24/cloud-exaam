#!/bin/bash
# =============================================================================
# MediScan Africa — Script 02 : Déploiement EC2 + API Flask
# À exécuter APRÈS 01_deploy_infrastructure.sh
# =============================================================================

source /tmp/mediscan_infra_ids.env

echo "======================================================"
echo "  MediScan Africa — Déploiement EC2 + API Flask"
echo "======================================================"

# ─── ÉTAPE 1 : KEY PAIR ───────────────────────────────────────────────────────
echo ""
echo "[1/3] Création de la clé SSH..."

aws ec2 create-key-pair \
    --key-name "$PROJECT-keypair" \
    --query 'KeyMaterial' \
    --output text > ~/.ssh/$PROJECT-keypair.pem

chmod 400 ~/.ssh/$PROJECT-keypair.pem

echo "  ✅ Clé SSH : ~/.ssh/$PROJECT-keypair.pem"
echo "  ⚠️  Gardez ce fichier en sécurité !"

# ─── ÉTAPE 2 : USER DATA (script d'initialisation EC2) ────────────────────────
echo ""
echo "[2/3] Préparation du User Data..."

cat > /tmp/userdata.sh << USERDATA
#!/bin/bash
# Script d'initialisation automatique de l'instance EC2 MediScan

# Mise à jour système
yum update -y

# Installation Python 3.11, pip, git
yum install -y python3.11 python3.11-pip git

# Installation des dépendances Python
pip3.11 install flask boto3 scikit-learn pandas numpy joblib gunicorn

# Répertoire de l'application
mkdir -p /opt/mediscan
cd /opt/mediscan

# Télécharger l'API depuis S3 (sera uploadée manuellement)
aws s3 cp s3://$BUCKET_NAME/app/ /opt/mediscan/ --recursive || true

# Variables d'environnement
echo "export S3_BUCKET=$BUCKET_NAME" >> /etc/environment
echo "export AWS_DEFAULT_REGION=$REGION" >> /etc/environment
echo "export FLASK_ENV=production" >> /etc/environment

# Service systemd pour API Flask
cat > /etc/systemd/system/mediscan.service << 'EOF'
[Unit]
Description=MediScan Africa API
After=network.target

[Service]
Type=simple
User=ec2-user
WorkingDirectory=/opt/mediscan
ExecStart=/usr/local/bin/gunicorn --workers 2 --bind 0.0.0.0:5000 app:app
Restart=always
RestartSec=10
Environment=FLASK_ENV=production

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable mediscan
# (sera démarré après déploiement du code)

# Installation agent CloudWatch
yum install -y amazon-cloudwatch-agent
USERDATA

# ─── ÉTAPE 3 : LANCEMENT EC2 ──────────────────────────────────────────────────
echo ""
echo "[3/3] Lancement de l'instance EC2..."

# AMI Amazon Linux 2023 (eu-west-1) — Free Tier eligible
AMI_ID=$(aws ec2 describe-images \
    --owners amazon \
    --filters "Name=name,Values=al2023-ami-*-x86_64" \
              "Name=state,Values=available" \
    --query 'Images | sort_by(@, &CreationDate) | [-1].ImageId' \
    --output text \
    --region $REGION)

INSTANCE_ID=$(aws ec2 run-instances \
    --image-id $AMI_ID \
    --instance-type t2.micro \
    --key-name "$PROJECT-keypair" \
    --security-group-ids $SG_EC2 \
    --subnet-id $SUBNET_PUBLIC \
    --iam-instance-profile Name="$PROJECT-ec2-profile" \
    --user-data file:///tmp/userdata.sh \
    --block-device-mappings '[{
        "DeviceName": "/dev/xvda",
        "Ebs": {
            "VolumeSize": 20,
            "VolumeType": "gp3",
            "DeleteOnTermination": true
        }
    }]' \
    --tag-specifications "ResourceType=instance,Tags=[
        {Key=Name,Value=$PROJECT-api},
        {Key=Project,Value=$PROJECT},
        {Key=Environment,Value=production}
    ]" \
    --query 'Instances[0].InstanceId' \
    --output text)

echo "  ✅ Instance EC2 lancée : $INSTANCE_ID"
echo "  ⏳ Attente que l'instance soit en cours d'exécution..."

aws ec2 wait instance-running --instance-ids $INSTANCE_ID
sleep 30

PUBLIC_IP=$(aws ec2 describe-instances \
    --instance-ids $INSTANCE_ID \
    --query 'Reservations[0].Instances[0].PublicIpAddress' \
    --output text)

echo ""
echo "======================================================"
echo "  ✅ EC2 DÉPLOYÉ"
echo "======================================================"
echo "  Instance ID  : $INSTANCE_ID"
echo "  IP Publique  : $PUBLIC_IP"
echo "  SSH          : ssh -i ~/.ssh/$PROJECT-keypair.pem ec2-user@$PUBLIC_IP"
echo "  API URL      : http://$PUBLIC_IP:5000"
echo ""
echo "  Prochaine étape : ./03_deploy_rds.sh"
echo "  Puis uploader l'API : ./04_upload_app.sh"

# Sauvegarder l'IP publique
echo "export INSTANCE_ID=\"$INSTANCE_ID\"" >> /tmp/mediscan_infra_ids.env
echo "export PUBLIC_IP=\"$PUBLIC_IP\"" >> /tmp/mediscan_infra_ids.env
