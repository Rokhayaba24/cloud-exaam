#!/bin/bash
# =============================================================================
# MediScan Africa — Script 05 : CloudWatch Dashboard + Alarmes
# =============================================================================

source /tmp/mediscan_infra_ids.env

echo "======================================================"
echo "  MediScan Africa — Configuration CloudWatch"
echo "======================================================"

# ─── ALARME 1 : Latence API > 2 secondes ──────────────────────────────────────
echo "[1/5] Alarme latence API..."

aws cloudwatch put-metric-alarm \
    --alarm-name "$PROJECT-latence-api" \
    --alarm-description "Latence API MediScan > 2000ms" \
    --namespace "MediScanAfrica" \
    --metric-name "InferenceLatencyMs" \
    --statistic Average \
    --period 60 \
    --evaluation-periods 2 \
    --threshold 2000 \
    --comparison-operator GreaterThanThreshold \
    --alarm-actions "arn:aws:sns:$REGION:$(aws sts get-caller-identity --query Account --output text):mediscan-alerts" \
    --treat-missing-data notBreaching \
    --region $REGION

echo "  ✅ Alarme latence > 2s"

# ─── ALARME 2 : Taux d'erreurs API > 1% ──────────────────────────────────────
echo "[2/5] Alarme erreurs API..."

aws cloudwatch put-metric-alarm \
    --alarm-name "$PROJECT-erreurs-api" \
    --alarm-description "Taux d'erreurs API MediScan > 1%" \
    --namespace "MediScanAfrica" \
    --metric-name "APIErrors" \
    --statistic Sum \
    --period 300 \
    --evaluation-periods 1 \
    --threshold 5 \
    --comparison-operator GreaterThanThreshold \
    --treat-missing-data notBreaching \
    --region $REGION

echo "  ✅ Alarme erreurs API > 5/5min"

# ─── ALARME 3 : CPU EC2 > 80% ─────────────────────────────────────────────────
echo "[3/5] Alarme CPU EC2..."

aws cloudwatch put-metric-alarm \
    --alarm-name "$PROJECT-cpu-ec2" \
    --alarm-description "CPU EC2 MediScan > 80%" \
    --namespace "AWS/EC2" \
    --metric-name "CPUUtilization" \
    --dimensions Name=InstanceId,Value=$INSTANCE_ID \
    --statistic Average \
    --period 300 \
    --evaluation-periods 2 \
    --threshold 80 \
    --comparison-operator GreaterThanThreshold \
    --treat-missing-data breaching \
    --region $REGION

echo "  ✅ Alarme CPU EC2 > 80%"

# ─── ALARME 4 : Connexions RDS > 80 ──────────────────────────────────────────
echo "[4/5] Alarme connexions RDS..."

aws cloudwatch put-metric-alarm \
    --alarm-name "$PROJECT-connexions-rds" \
    --alarm-description "Connexions RDS MediScan > 80" \
    --namespace "AWS/RDS" \
    --metric-name "DatabaseConnections" \
    --dimensions Name=DBInstanceIdentifier,Value="$PROJECT-mysql" \
    --statistic Average \
    --period 60 \
    --evaluation-periods 3 \
    --threshold 80 \
    --comparison-operator GreaterThanThreshold \
    --treat-missing-data notBreaching \
    --region $REGION

echo "  ✅ Alarme connexions RDS > 80"

# ─── ALARME 5 : Disponibilité API < 99% ───────────────────────────────────────
echo "[5/5] Dashboard CloudWatch unifié..."

aws cloudwatch put-dashboard \
    --dashboard-name "$PROJECT-dashboard" \
    --dashboard-body '{
        "widgets": [
            {
                "type": "text",
                "x": 0, "y": 0, "width": 24, "height": 2,
                "properties": {
                    "markdown": "# 🏥 MediScan Africa — Dashboard de Production\nSurveillance temps réel | API Flask sur EC2 | Modèles ML : Diabète + Cancer"
                }
            },
            {
                "type": "metric",
                "x": 0, "y": 2, "width": 8, "height": 6,
                "properties": {
                    "title": "Latence Inférence (ms)",
                    "metrics": [["MediScanAfrica", "InferenceLatencyMs", {"stat": "Average", "color": "#2196F3"}]],
                    "period": 60, "view": "timeSeries",
                    "annotations": {"horizontal": [{"value": 2000, "label": "Seuil critique 2s", "color": "#F44336"}]}
                }
            },
            {
                "type": "metric",
                "x": 8, "y": 2, "width": 8, "height": 6,
                "properties": {
                    "title": "Diagnostics par scénario",
                    "metrics": [
                        ["MediScanAfrica", "Diagnostics_A_diabete", {"label": "Diabète", "color": "#FF9800"}],
                        ["MediScanAfrica", "Diagnostics_B_cancer", {"label": "Cancer", "color": "#E91E63"}]
                    ],
                    "period": 300, "view": "timeSeries"
                }
            },
            {
                "type": "metric",
                "x": 16, "y": 2, "width": 8, "height": 6,
                "properties": {
                    "title": "Erreurs API + Cache Hits",
                    "metrics": [
                        ["MediScanAfrica", "APIErrors", {"label": "Erreurs", "color": "#F44336"}],
                        ["MediScanAfrica", "CacheHits", {"label": "Cache Hits", "color": "#4CAF50"}],
                        ["MediScanAfrica", "CacheMisses", {"label": "Cache Misses", "color": "#9E9E9E"}]
                    ],
                    "period": 300, "view": "timeSeries"
                }
            },
            {
                "type": "metric",
                "x": 0, "y": 8, "width": 12, "height": 6,
                "properties": {
                    "title": "CPU EC2 (%)",
                    "metrics": [["AWS/EC2", "CPUUtilization", "InstanceId", "'$INSTANCE_ID'"]],
                    "period": 60, "view": "timeSeries",
                    "annotations": {"horizontal": [{"value": 80, "label": "Seuil 80%", "color": "#FF5722"}]}
                }
            },
            {
                "type": "metric",
                "x": 12, "y": 8, "width": 12, "height": 6,
                "properties": {
                    "title": "Connexions RDS Aurora",
                    "metrics": [["AWS/RDS", "DatabaseConnections", "DBInstanceIdentifier", "'$PROJECT-mysql'"]],
                    "period": 60, "view": "timeSeries",
                    "annotations": {"horizontal": [{"value": 80, "label": "Seuil 80 conn.", "color": "#FF5722"}]}
                }
            }
        ]
    }' \
    --region $REGION

echo ""
echo "======================================================"
echo "  ✅ CLOUDWATCH CONFIGURÉ"
echo "======================================================"
echo ""
echo "  Dashboard : https://console.aws.amazon.com/cloudwatch/home?region=$REGION#dashboards:name=$PROJECT-dashboard"
echo "  Alarmes   : 5 alarmes créées"
