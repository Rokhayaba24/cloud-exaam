from flask import Flask, request, jsonify
import joblib
import numpy as np

import pymysql

DB_HOST = "mediscan-db.c5c6u8ecuqba.eu-west-1.rds.amazonaws.com"
DB_USER = "admin"
DB_PASS = "MediScan2025!"
DB_NAME = "mediscan_db"

def get_db():
    return pymysql.connect(
        host=DB_HOST, user=DB_USER,
        password=DB_PASS, database=DB_NAME,
        cursorclass=pymysql.cursors.DictCursor
    )

app = Flask(__name__)

diabete_model = joblib.load("models/diabete_model.pkl")
cancer_model  = joblib.load("models/cancer_model.pkl")

# ── Helpers recommandations ──────────────────────────────────────────
def niveau_diabete(proba):
    if proba >= 0.75:
        return "URGENCE", "Glycemie capillaire immediate. Consultation diabetologue sous 48h.", ["Glycemie a jeun", "HbA1c", "Bilan renal"]
    elif proba >= 0.5:
        return "CONSULTATION", "Consultation specialisee dans le mois. Surveiller alimentation.", ["HbA1c", "Glycemie postprandiale"]
    elif proba >= 0.3:
        return "SURVEILLANCE", "Controle glycemique dans 6 mois. Activite physique recommandee.", ["Glycemie a jeun dans 6 mois"]
    else:
        return "SURVEILLANCE", "Risque faible. Mode de vie sain recommande.", ["Depistage standard dans 3 ans"]

def niveau_cancer(proba):
    if proba >= 0.7:
        return "URGENCE", "Biopsie complementaire urgente. Referer oncologue sous 72h.", ["Biopsie tissulaire", "Scanner thoracique", "Marqueurs tumoraux"]
    elif proba >= 0.4:
        return "CONSULTATION", "Echographie complementaire recommandee. Avis specialise sous 2 semaines.", ["Echographie mammaire", "IRM si disponible"]
    else:
        return "SURVEILLANCE", "Suivi mammographique annuel recommande.", ["Mammographie annuelle"]

# ── HEALTH CHECK ─────────────────────────────────────────────────────
@app.route('/health', methods=['GET'])
def health():
    return jsonify({"status": "ok", "service": "MediScan Africa"}), 200

# ── POST /diagnostic ─────────────────────────────────────────────────
@app.route('/diagnostic', methods=['POST'])
def diagnostic():
    try:
        data     = request.get_json()
        scenario = data.get("scenario")
        features = data.get("features", {})

        if scenario == "A_diabete":
            X = np.array([[
                features.get("Pregnancies", 0),
                features.get("Glucose", 0),
                features.get("BloodPressure", 0),
                features.get("SkinThickness", 0),
                features.get("Insulin", 0),
                features.get("BMI", 0),
                features.get("DiabetesPedigreeFunction", 0),
                features.get("Age", 0)
            ]])
            proba      = float(diabete_model.predict_proba(X)[0][1])
            urgence, recommandation, examens = niveau_diabete(proba)
            diagnostic_principal = "Diabete de type 2 detecte" if proba >= 0.5 else "Pas de diabete detecte"

        elif scenario == "B_cancer":
            X = np.array([features.get("features_list", [0]*30)])
            proba      = float(cancer_model.predict_proba(X)[0][1])
            urgence, recommandation, examens = niveau_cancer(proba)
            diagnostic_principal = "Tumeur maligne detectee" if proba >= 0.5 else "Tumeur benigne"

        else:
            return jsonify({"erreur": "scenario invalide. Utiliser A_diabete ou B_cancer"}), 400

        return jsonify({
            "scenario":              scenario,
            "diagnostic_principal":  diagnostic_principal,
            "probabilite":           round(proba, 4),
            "score_risque":          round(proba * 100, 1),
            "urgence":               urgence,
            "recommandation":        recommandation,
            "examens_recommandes":   examens,
            "disclaimer":            "Resultat indicatif. Ne remplace pas un avis medical."
        }), 200

    except KeyError as e:
        return jsonify({"erreur": f"Champ manquant : {str(e)}"}), 400
    except Exception as e:
        return jsonify({"erreur": str(e)}), 500

# ── GET /patient/{id}/historique ──────────────────────────────────────
@app.route('/patient/<int:patient_id>/historique', methods=['GET'])
def historique(patient_id):
    try:
        conn = get_db()
        with conn.cursor() as cursor:
            cursor.execute(
                "SELECT * FROM consultations WHERE patient_id=%s ORDER BY date_consultation DESC LIMIT 10",
                (patient_id,)
            )
            rows = cursor.fetchall()
        conn.close()
        return jsonify({"patient_id": patient_id, "consultations": rows}), 200
    except Exception as e:
        return jsonify({"erreur": str(e)}), 500
    
# ── GET /stats/aggregees ──────────────────────────────────────────────
@app.route('/stats/aggregees', methods=['GET'])
def stats():
    try:
        conn = get_db()
        with conn.cursor() as cursor:
            cursor.execute("SELECT COUNT(*) as total FROM consultations")
            total = cursor.fetchone()["total"]
            cursor.execute("SELECT COUNT(*) as n FROM consultations WHERE scenario='A_diabete' AND score_risque >= 0.5")
            diab = cursor.fetchone()["n"]
            cursor.execute("SELECT COUNT(*) as n FROM consultations WHERE scenario='B_cancer' AND score_risque >= 0.5")
            cancer = cursor.fetchone()["n"]
        conn.close()
        return jsonify({
            "total_diagnostics": total,
            "cas_diabete": diab,
            "cas_cancer_malin": cancer
        }), 200
    except Exception as e:
        return jsonify({"erreur": str(e)}), 500

# ── Anciennes routes (compatibilité) ─────────────────────────────────
@app.route('/diabete', methods=['POST'])
def predict_diabete():
    try:
        data = request.get_json()
        X    = np.array([[data["Pregnancies"], data["Glucose"], data["BloodPressure"],
                          data["SkinThickness"], data["Insulin"], data["BMI"],
                          data["DiabetesPedigreeFunction"], data["Age"]]])
        proba = float(diabete_model.predict_proba(X)[0][1])
        return jsonify({"diagnostic": "diabete" if proba >= 0.5 else "non diabete",
                        "probabilite": round(proba, 4)}), 200
    except Exception as e:
        return jsonify({"erreur": str(e)}), 500

@app.route('/cancer', methods=['POST'])
def predict_cancer():
    try:
        data  = request.get_json()
        X     = np.array([data["features"]]).reshape(1, -1)
        proba = float(cancer_model.predict_proba(X)[0][1])
        return jsonify({"diagnostic": "malin" if proba >= 0.5 else "benin",
                        "probabilite": round(proba, 4)}), 200
    except Exception as e:
        return jsonify({"erreur": str(e)}), 500

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=False)