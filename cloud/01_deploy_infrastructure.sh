#!/bin/bash
# =============================================================================
# MediScan Africa — Projet P-10 — ISI Dakar 2025-2026
# Script 01 : Déploiement de l'infrastructure AWS (VPC, SG, S3, IAM)
# Exécuter dans AWS CloudShell ou avec AWS CLI configuré
# =============================================================================

set -e  # Arrêter si une commande échoue

# ─── CONFIGURATION — modifier ces variables ───────────────────────────────────
REGION="eu-west-1"             # Région AWS (Paris ou Ireland pour Free Tier)
PROJECT="mediscan-africa"      # Préfixe pour toutes les ressources
BUCKET_NAME="mediscan-africa-$(aws sts get-caller-identity --query Account --output text)"
YOUR_IP=$(curl -s https://checkip.amazonaws.com)/32   # Votre IP publique

echo "======================================================"
echo "  MediScan Africa — Déploiement Infrastructure AWS"
echo "  Région : $REGION"
echo "  Bucket : $BUCKET_NAME"
echo "  Votre IP : $YOUR_IP"
echo "======================================================"

# ─── ÉTAPE 1 : VPC ────────────────────────────────────────────────────────────
echo ""
echo "[1/8] Création du VPC..."

VPC_ID=$(aws ec2 create-vpc \
    --cidr-block 10.0.0.0/16 \
    --region $REGION \
    --query 'Vpc.VpcId' \
    --output text)

aws ec2 create-tags \
    --resources $VPC_ID \
    --tags Key=Name,Value="$PROJECT-vpc" Key=Project,Value=$PROJECT

aws ec2 modify-vpc-attribute \
    --vpc-id $VPC_ID \
    --enable-dns-hostnames

echo "  ✅ VPC créé : $VPC_ID"

# ─── ÉTAPE 2 : SOUS-RÉSEAUX ───────────────────────────────────────────────────
echo ""
echo "[2/8] Création des sous-réseaux..."

# Récupérer la première AZ disponible
AZ=$(aws ec2 describe-availability-zones \
    --region $REGION \
    --query 'AvailabilityZones[0].ZoneName' \
    --output text)

# Sous-réseau PUBLIC (EC2 + Lambda)
SUBNET_PUBLIC=$(aws ec2 create-subnet \
    --vpc-id $VPC_ID \
    --cidr-block 10.0.1.0/24 \
    --availability-zone $AZ \
    --query 'Subnet.SubnetId' \
    --output text)

aws ec2 create-tags \
    --resources $SUBNET_PUBLIC \
    --tags Key=Name,Value="$PROJECT-subnet-public" Key=Type,Value=public

aws ec2 modify-subnet-attribute \
    --subnet-id $SUBNET_PUBLIC \
    --map-public-ip-on-launch

# Sous-réseau PRIVÉ (RDS Aurora)
SUBNET_PRIVATE=$(aws ec2 create-subnet \
    --vpc-id $VPC_ID \
    --cidr-block 10.0.2.0/24 \
    --availability-zone $AZ \
    --query 'Subnet.SubnetId' \
    --output text)

aws ec2 create-tags \
    --resources $SUBNET_PRIVATE \
    --tags Key=Name,Value="$PROJECT-subnet-private" Key=Type,Value=private

echo "  ✅ Sous-réseau public : $SUBNET_PUBLIC"
echo "  ✅ Sous-réseau privé  : $SUBNET_PRIVATE"

# ─── ÉTAPE 3 : INTERNET GATEWAY ───────────────────────────────────────────────
echo ""
echo "[3/8] Création de l'Internet Gateway..."

IGW_ID=$(aws ec2 create-internet-gateway \
    --query 'InternetGateway.InternetGatewayId' \
    --output text)

aws ec2 attach-internet-gateway \
    --internet-gateway-id $IGW_ID \
    --vpc-id $VPC_ID

aws ec2 create-tags \
    --resources $IGW_ID \
    --tags Key=Name,Value="$PROJECT-igw"

# Route table pour sous-réseau public
RT_ID=$(aws ec2 create-route-table \
    --vpc-id $VPC_ID \
    --query 'RouteTable.RouteTableId' \
    --output text)

aws ec2 create-route \
    --route-table-id $RT_ID \
    --destination-cidr-block 0.0.0.0/0 \
    --gateway-id $IGW_ID

aws ec2 associate-route-table \
    --route-table-id $RT_ID \
    --subnet-id $SUBNET_PUBLIC

echo "  ✅ Internet Gateway : $IGW_ID"

# ─── ÉTAPE 4 : SECURITY GROUPS ────────────────────────────────────────────────
echo ""
echo "[4/8] Création des Security Groups..."

# SG pour EC2 (API Flask)
SG_EC2=$(aws ec2 create-security-group \
    --group-name "$PROJECT-ec2-sg" \
    --description "Security Group EC2 - API MediScan" \
    --vpc-id $VPC_ID \
    --query 'GroupId' \
    --output text)

# SSH uniquement depuis votre IP
aws ec2 authorize-security-group-ingress \
    --group-id $SG_EC2 \
    --protocol tcp --port 22 \
    --cidr $YOUR_IP

# HTTP/HTTPS public
aws ec2 authorize-security-group-ingress \
    --group-id $SG_EC2 \
    --protocol tcp --port 80 \
    --cidr 0.0.0.0/0

aws ec2 authorize-security-group-ingress \
    --group-id $SG_EC2 \
    --protocol tcp --port 5000 \
    --cidr 0.0.0.0/0

# SG pour RDS Aurora
SG_RDS=$(aws ec2 create-security-group \
    --group-name "$PROJECT-rds-sg" \
    --description "Security Group RDS - Base de données privée" \
    --vpc-id $VPC_ID \
    --query 'GroupId' \
    --output text)

# Port 3306 uniquement depuis EC2-SG (JAMAIS depuis Internet)
aws ec2 authorize-security-group-ingress \
    --group-id $SG_RDS \
    --protocol tcp --port 3306 \
    --source-group $SG_EC2

echo "  ✅ SG EC2 : $SG_EC2  (22/SSH depuis $YOUR_IP | 80/5000 public)"
echo "  ✅ SG RDS : $SG_RDS  (3306 depuis EC2-SG uniquement)"

# ─── ÉTAPE 5 : S3 BUCKET ──────────────────────────────────────────────────────
echo ""
echo "[5/8] Création du bucket S3..."

# Créer le bucket (pour eu-west-1 ou autre région non us-east-1)
if [ "$REGION" = "us-east-1" ]; then
    aws s3api create-bucket \
        --bucket $BUCKET_NAME \
        --region $REGION
else
    aws s3api create-bucket \
        --bucket $BUCKET_NAME \
        --region $REGION \
        --create-bucket-configuration LocationConstraint=$REGION
fi

# Activer le versioning
aws s3api put-bucket-versioning \
    --bucket $BUCKET_NAME \
    --versioning-configuration Status=Enabled

# Chiffrement SSE-S3
aws s3api put-bucket-encryption \
    --bucket $BUCKET_NAME \
    --server-side-encryption-configuration '{
        "Rules": [{
            "ApplyServerSideEncryptionByDefault": {
                "SSEAlgorithm": "AES256"
            }
        }]
    }'

# Bloquer accès public
aws s3api put-public-access-block \
    --bucket $BUCKET_NAME \
    --public-access-block-configuration \
        "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"

# Lifecycle : optimisation des coûts
aws s3api put-bucket-lifecycle-configuration \
    --bucket $BUCKET_NAME \
    --lifecycle-configuration '{
        "Rules": [{
            "ID": "models-lifecycle",
            "Status": "Enabled",
            "Filter": {"Prefix": "models/"},
            "Transitions": [
                {"Days": 90, "StorageClass": "STANDARD_IA"}
            ]
        }, {
            "ID": "datasets-lifecycle",
            "Status": "Enabled",
            "Filter": {"Prefix": "datasets/"},
            "Transitions": [
                {"Days": 30, "StorageClass": "STANDARD_IA"},
                {"Days": 90, "StorageClass": "GLACIER"}
            ]
        }]
    }'

# Créer la structure de dossiers
for folder in models/diabete/v1.0 models/cancer/v1.0 datasets reports; do
    aws s3api put-object \
        --bucket $BUCKET_NAME \
        --key "$folder/" > /dev/null
done

echo "  ✅ Bucket S3 : $BUCKET_NAME"
echo "     - Versioning activé"
echo "     - Chiffrement SSE-S3"
echo "     - Lifecycle configuré"

# ─── ÉTAPE 6 : IAM ROLES ──────────────────────────────────────────────────────
echo ""
echo "[6/8] Création des rôles IAM..."

# Rôle pour EC2 (accès S3 en lecture + DynamoDB + CloudWatch)
cat > /tmp/ec2-trust-policy.json << 'EOF'
{
    "Version": "2012-10-17",
    "Statement": [{
        "Effect": "Allow",
        "Principal": {"Service": "ec2.amazonaws.com"},
        "Action": "sts:AssumeRole"
    }]
}
EOF

aws iam create-role \
    --role-name "$PROJECT-ec2-role" \
    --assume-role-policy-document file:///tmp/ec2-trust-policy.json \
    --description "Role EC2 MediScan Africa" \
    > /dev/null

# Politique minimale pour EC2 (least-privilege)
cat > /tmp/ec2-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "S3ReadModels",
            "Effect": "Allow",
            "Action": ["s3:GetObject", "s3:ListBucket"],
            "Resource": [
                "arn:aws:s3:::$BUCKET_NAME",
                "arn:aws:s3:::$BUCKET_NAME/models/*"
            ]
        },
        {
            "Sid": "S3WriteReports",
            "Effect": "Allow",
            "Action": ["s3:PutObject"],
            "Resource": "arn:aws:s3:::$BUCKET_NAME/reports/*"
        },
        {
            "Sid": "DynamoDBCache",
            "Effect": "Allow",
            "Action": [
                "dynamodb:GetItem", "dynamodb:PutItem",
                "dynamodb:Query", "dynamodb:Scan"
            ],
            "Resource": "arn:aws:dynamodb:$REGION:*:table/mediscan-*"
        },
        {
            "Sid": "CloudWatchLogs",
            "Effect": "Allow",
            "Action": [
                "logs:CreateLogGroup", "logs:CreateLogStream",
                "logs:PutLogEvents",
                "cloudwatch:PutMetricData"
            ],
            "Resource": "*"
        }
    ]
}
EOF

aws iam put-role-policy \
    --role-name "$PROJECT-ec2-role" \
    --policy-name "$PROJECT-ec2-policy" \
    --policy-document file:///tmp/ec2-policy.json

# Instance profile pour attacher le rôle à EC2
aws iam create-instance-profile \
    --instance-profile-name "$PROJECT-ec2-profile" > /dev/null

aws iam add-role-to-instance-profile \
    --instance-profile-name "$PROJECT-ec2-profile" \
    --role-name "$PROJECT-ec2-role"

echo "  ✅ IAM Role EC2 : $PROJECT-ec2-role"

# Rôle pour Lambda
cat > /tmp/lambda-trust-policy.json << 'EOF'
{
    "Version": "2012-10-17",
    "Statement": [{
        "Effect": "Allow",
        "Principal": {"Service": "lambda.amazonaws.com"},
        "Action": "sts:AssumeRole"
    }]
}
EOF

aws iam create-role \
    --role-name "$PROJECT-lambda-role" \
    --assume-role-policy-document file:///tmp/lambda-trust-policy.json \
    --description "Role Lambda MediScan Africa" \
    > /dev/null

cat > /tmp/lambda-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "S3Models",
            "Effect": "Allow",
            "Action": ["s3:GetObject", "s3:PutObject", "s3:ListBucket", "s3:CopyObject"],
            "Resource": [
                "arn:aws:s3:::$BUCKET_NAME",
                "arn:aws:s3:::$BUCKET_NAME/models/*"
            ]
        },
        {
            "Sid": "DynamoDB",
            "Effect": "Allow",
            "Action": ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:Query"],
            "Resource": "arn:aws:dynamodb:$REGION:*:table/mediscan-*"
        },
        {
            "Sid": "CloudWatchLambda",
            "Effect": "Allow",
            "Action": [
                "logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents",
                "cloudwatch:PutMetricData"
            ],
            "Resource": "*"
        }
    ]
}
EOF

aws iam put-role-policy \
    --role-name "$PROJECT-lambda-role" \
    --policy-name "$PROJECT-lambda-policy" \
    --policy-document file:///tmp/lambda-policy.json

echo "  ✅ IAM Role Lambda : $PROJECT-lambda-role"

# ─── ÉTAPE 7 : DYNAMODB ───────────────────────────────────────────────────────
echo ""
echo "[7/8] Création des tables DynamoDB..."

# Table cache des diagnostics
aws dynamodb create-table \
    --table-name "mediscan-cache-diagnostics" \
    --attribute-definitions \
        AttributeName=pk_features_hash,AttributeType=S \
        AttributeName=model_version,AttributeType=S \
    --key-schema \
        AttributeName=pk_features_hash,KeyType=HASH \
        AttributeName=model_version,KeyType=RANGE \
    --billing-mode PAY_PER_REQUEST \
    --region $REGION > /dev/null

# Activer TTL (24h = 86400 secondes)
sleep 5  # Attendre que la table soit active
aws dynamodb update-time-to-live \
    --table-name "mediscan-cache-diagnostics" \
    --time-to-live-specification "Enabled=true,AttributeName=ttl" \
    --region $REGION > /dev/null 2>&1 || true

echo "  ✅ Table DynamoDB : mediscan-cache-diagnostics (TTL 24h)"

# ─── ÉTAPE 8 : EXPORT DES VARIABLES ──────────────────────────────────────────
echo ""
echo "[8/8] Sauvegarde des IDs de ressources..."

cat > /tmp/mediscan_infra_ids.env << EOF
# MediScan Africa — IDs d'infrastructure (généré le $(date))
export REGION="$REGION"
export PROJECT="$PROJECT"
export VPC_ID="$VPC_ID"
export SUBNET_PUBLIC="$SUBNET_PUBLIC"
export SUBNET_PRIVATE="$SUBNET_PRIVATE"
export IGW_ID="$IGW_ID"
export SG_EC2="$SG_EC2"
export SG_RDS="$SG_RDS"
export BUCKET_NAME="$BUCKET_NAME"
EOF

echo "  ✅ Variables sauvegardées dans /tmp/mediscan_infra_ids.env"
echo ""
echo "======================================================"
echo "  ✅ INFRASTRUCTURE DÉPLOYÉE AVEC SUCCÈS"
echo "======================================================"
echo ""
echo "  Prochaine étape : ./02_deploy_ec2.sh"
echo "  Prochaine étape : ./03_deploy_rds.sh"
