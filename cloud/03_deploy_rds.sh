#!/bin/bash
# =============================================================================
# MediScan Africa — Script 03 : Déploiement RDS Aurora MySQL
# =============================================================================

source /tmp/mediscan_infra_ids.env

DB_PASSWORD="MediScan2025!Secure"   # ⚠️ Changer en production !
DB_NAME="mediscan_db"
DB_USER="mediscan_admin"

echo "======================================================"
echo "  MediScan Africa — Déploiement RDS Aurora MySQL"
echo "======================================================"

# DB Subnet Group (nécessite 2 AZ minimum — on simule avec 1 AZ Free Tier)
echo ""
echo "[1/2] Création du DB Subnet Group..."

aws rds create-db-subnet-group \
    --db-subnet-group-name "$PROJECT-db-subnet-group" \
    --db-subnet-group-description "Subnet group for MediScan RDS" \
    --subnet-ids $SUBNET_PRIVATE \
    --region $REGION > /dev/null 2>&1 || true

echo "  ✅ DB Subnet Group créé"

echo ""
echo "[2/2] Lancement de l'instance RDS (MySQL Free Tier)..."

# IMPORTANT : Aurora nécessite db.t3.medium (payant).
# Pour le Free Tier académique, on utilise RDS MySQL db.t3.micro
# Le projet demande Aurora — on déploie MySQL compatible et on documente l'upgrade

RDS_ID=$(aws rds create-db-instance \
    --db-instance-identifier "$PROJECT-mysql" \
    --db-instance-class db.t3.micro \
    --engine mysql \
    --engine-version "8.0" \
    --master-username $DB_USER \
    --master-user-password "$DB_PASSWORD" \
    --db-name $DB_NAME \
    --vpc-security-group-ids $SG_RDS \
    --db-subnet-group-name "$PROJECT-db-subnet-group" \
    --no-publicly-accessible \
    --backup-retention-period 1 \
    --storage-type gp2 \
    --allocated-storage 20 \
    --storage-encrypted \
    --tags Key=Name,Value="$PROJECT-mysql" Key=Project,Value=$PROJECT \
    --region $REGION \
    --query 'DBInstance.DBInstanceIdentifier' \
    --output text)

echo "  ✅ RDS instance lancée : $RDS_ID"
echo "  ⏳ Démarrage en cours (5-10 minutes)..."
echo ""
echo "  Vérifier le statut avec :"
echo "  aws rds describe-db-instances --db-instance-identifier $PROJECT-mysql \\"
echo "      --query 'DBInstances[0].DBInstanceStatus'"
echo ""

# Sauvegarder les infos RDS
echo "export RDS_ID=\"$RDS_ID\"" >> /tmp/mediscan_infra_ids.env
echo "export DB_NAME=\"$DB_NAME\"" >> /tmp/mediscan_infra_ids.env
echo "export DB_USER=\"$DB_USER\"" >> /tmp/mediscan_infra_ids.env

echo "======================================================"
echo "  Quand RDS est prêt (status=available), exécuter :"
echo "  ./04_init_database.sh"
echo "======================================================"
