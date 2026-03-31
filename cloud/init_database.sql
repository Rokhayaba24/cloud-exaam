-- =============================================================================
-- MediScan Africa — Script SQL : Création base de données
-- Exécuter sur l'instance EC2 via : mysql -h <RDS_ENDPOINT> -u mediscan_admin -p mediscan_db < init_db.sql
-- =============================================================================

-- ─── TABLE 1 : patients_fictifs ───────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS patients_fictifs (
    id              INT AUTO_INCREMENT PRIMARY KEY,
    age             INT NOT NULL CHECK (age BETWEEN 1 AND 120),
    sexe            ENUM('M', 'F', 'Autre') NOT NULL,
    region_anon     VARCHAR(50) NOT NULL COMMENT 'Région anonymisée (ex: Centre-Ouest)',
    imc             DECIMAL(5,2) COMMENT 'Indice de Masse Corporelle',
    antecedents     JSON COMMENT 'Antécédents familiaux en JSON',
    date_creation   DATETIME DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_region (region_anon),
    INDEX idx_age (age)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='Patients fictifs anonymisés - usage académique uniquement';

-- ─── TABLE 2 : consultations ──────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS consultations (
    id                      INT AUTO_INCREMENT PRIMARY KEY,
    patient_id              INT NOT NULL,
    date_consultation       DATETIME DEFAULT CURRENT_TIMESTAMP,
    symptomes_json          JSON NOT NULL COMMENT 'Features du patient en JSON',
    scenario                ENUM('A_diabete', 'B_cancer') NOT NULL,
    score_risque            DECIMAL(5,4) NOT NULL COMMENT 'Probabilité 0.0-1.0',
    diagnostic_principal    VARCHAR(100) NOT NULL,
    niveau_urgence          ENUM('URGENCE', 'CONSULTATION', 'SURVEILLANCE') NOT NULL,
    recommandations         TEXT,
    modele_version          VARCHAR(20) NOT NULL DEFAULT 'v1.0',
    medecin_fictif          VARCHAR(50),
    FOREIGN KEY (patient_id) REFERENCES patients_fictifs(id) ON DELETE CASCADE,
    INDEX idx_patient (patient_id),
    INDEX idx_scenario (scenario),
    INDEX idx_date (date_consultation)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ─── TABLE 3 : modeles_historique ─────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS modeles_historique (
    id              INT AUTO_INCREMENT PRIMARY KEY,
    scenario        ENUM('A_diabete', 'B_cancer') NOT NULL,
    version         VARCHAR(20) NOT NULL,
    date_deploy     DATETIME DEFAULT CURRENT_TIMESTAMP,
    algorithme      VARCHAR(100) NOT NULL,
    s3_path         VARCHAR(255) NOT NULL COMMENT 'Chemin S3 du fichier .pkl',
    metriques_json  JSON NOT NULL COMMENT 'accuracy, auc, sensibilite, specificite, vpp, vpn',
    actif           BOOLEAN DEFAULT FALSE,
    notes           TEXT,
    UNIQUE KEY uq_scenario_version (scenario, version),
    INDEX idx_actif (actif)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ─── DONNÉES FICTIVES : patients ──────────────────────────────────────────────
INSERT INTO patients_fictifs (age, sexe, region_anon, imc, antecedents) VALUES
(45, 'F', 'Dakar-Plateau',     27.3, '{"diabete_famille": true, "cancer": false}'),
(38, 'F', 'Thiès-Nord',        31.1, '{"diabete_famille": false, "cancer": true}'),
(62, 'M', 'Saint-Louis',       24.8, '{"diabete_famille": true, "HTA": true}'),
(29, 'F', 'Ziguinchor',        22.5, '{"diabete_famille": false, "cancer": false}'),
(55, 'F', 'Kaolack-Centre',    33.7, '{"diabete_famille": true, "cancer": true}'),
(41, 'M', 'Louga',             26.2, '{"tabagisme": true}'),
(67, 'F', 'Diourbel',          29.9, '{"diabete_famille": true, "HTA": true}'),
(34, 'F', 'Tambacounda',       20.1, '{"cancer": false}'),
(52, 'F', 'Matam',             35.4, '{"obese": true, "diabete_famille": true}'),
(48, 'M', 'Kolda',             23.7, '{}'),
(43, 'F', 'Sédhiou',           28.6, '{"cancer": true}'),
(59, 'F', 'Kédougou',          30.2, '{"diabete_famille": false}'),
(37, 'F', 'Fatick',            25.8, '{"cancer": false}'),
(71, 'F', 'Kaffrine',          26.4, '{"diabete_famille": true, "HTA": true}'),
(46, 'M', 'Dakar-Médina',      28.1, '{"tabagisme": true}'),
(33, 'F', 'Pikine',            22.9, '{}'),
(58, 'F', 'Guédiawaye',        31.6, '{"cancer": true, "diabete_famille": true}'),
(44, 'F', 'Rufisque',          27.4, '{"diabete_famille": false}'),
(65, 'F', 'Mbour',             29.3, '{"HTA": true, "diabete_famille": true}'),
(39, 'M', 'Tivaouane',         24.5, '{}');

-- ─── DONNÉES FICTIVES : consultations ─────────────────────────────────────────
INSERT INTO consultations (patient_id, symptomes_json, scenario, score_risque, diagnostic_principal, niveau_urgence, recommandations, modele_version, medecin_fictif) VALUES
(1, '{"grossesses":3,"glucose":148,"pression":72,"imc":27.3,"age":45}', 'A_diabete', 0.7821, 'Risque élevé de diabète de type 2', 'CONSULTATION', 'Glycémie à jeun, HGPO recommandés. Surveillance trimestrielle.', 'v1.0', 'Dr. Diallo F.'),
(2, '{"radius_mean":17.5,"texture_mean":21.3,"area_mean":840,"compactness_mean":0.15}', 'B_cancer', 0.8934, 'Classification : Malin (haute probabilité)', 'URGENCE', 'Biopsie complémentaire urgente. Référer oncologue.', 'v1.0', 'Dr. Sow A.'),
(3, '{"grossesses":2,"glucose":110,"pression":80,"imc":24.8,"age":62}', 'A_diabete', 0.4523, 'Risque modéré de diabète de type 2', 'SURVEILLANCE', 'HbA1c recommandée. Contrôle dans 6 mois.', 'v1.0', 'Dr. Ba M.'),
(4, '{"radius_mean":10.2,"texture_mean":14.5,"area_mean":320,"compactness_mean":0.07}', 'B_cancer', 0.0934, 'Classification : Bénin (faible probabilité)', 'SURVEILLANCE', 'Mammographie annuelle recommandée. Surveillance habituelle.', 'v1.0', 'Dr. Diallo F.'),
(5, '{"grossesses":5,"glucose":183,"pression":76,"imc":33.7,"age":55}', 'A_diabete', 0.9234, 'Risque très élevé de diabète de type 2', 'URGENCE', 'Glycémie capillaire immédiate. Consultation diabétologue sous 48h.', 'v1.0', 'Dr. Ndiaye K.'),
(6, '{"grossesses":0,"glucose":92,"pression":68,"imc":26.2,"age":41}', 'A_diabete', 0.1823, 'Risque faible de diabète de type 2', 'SURVEILLANCE', 'Dépistage standard dans 3 ans.', 'v1.0', 'Dr. Ba M.'),
(7, '{"grossesses":4,"glucose":165,"pression":90,"imc":29.9,"age":67}', 'A_diabete', 0.8567, 'Risque élevé de diabète de type 2', 'CONSULTATION', 'HbA1c + glycémie à jeun. Consultation spécialisée.', 'v1.0', 'Dr. Sow A.'),
(8, '{"radius_mean":11.8,"texture_mean":16.2,"area_mean":410,"compactness_mean":0.09}', 'B_cancer', 0.1234, 'Classification : Bénin (faible probabilité)', 'SURVEILLANCE', 'Suivi annuel recommandé.', 'v1.0', 'Dr. Diallo F.'),
(9, '{"grossesses":7,"glucose":195,"pression":84,"imc":35.4,"age":52}', 'A_diabete', 0.9612, 'Risque très élevé de diabète de type 2', 'URGENCE', 'Intervention urgente requise. Glycémie > seuil critique.', 'v1.0', 'Dr. Ndiaye K.'),
(10,'{"radius_mean":13.5,"texture_mean":19.8,"area_mean":560,"compactness_mean":0.11}', 'B_cancer', 0.3456, 'Classification : Indéterminé — contrôle recommandé', 'CONSULTATION', 'Échographie complémentaire. Avis spécialisé.', 'v1.0', 'Dr. Ba M.');

-- ─── DONNÉES FICTIVES : historique modèles ────────────────────────────────────
INSERT INTO modeles_historique (scenario, version, algorithme, s3_path, metriques_json, actif, notes) VALUES
('A_diabete', 'v1.0', 'Gradient Boosting', 
 's3://mediscan-africa/models/diabete/v1.0/model_diabete_v1.0.pkl',
 '{"accuracy": 0.7922, "roc_auc": 0.8534, "sensibilite": 0.7812, "specificite": 0.7987, "vpp": 0.6923, "vpn": 0.8567}',
 TRUE, 'Modèle initial - dataset Pima Indians (768 patients)'),
('B_cancer', 'v1.0', 'SVM (RBF)',
 's3://mediscan-africa/models/cancer/v1.0/model_cancer_v1.0.pkl',
 '{"accuracy": 0.9736, "roc_auc": 0.9945, "sensibilite": 0.9762, "specificite": 0.9718, "vpp": 0.9532, "vpn": 0.9876}',
 TRUE, 'Modèle initial - dataset Wisconsin (569 cas)');

-- ─── VÉRIFICATION ─────────────────────────────────────────────────────────────
SELECT '=== RÉSUMÉ BASE DE DONNÉES ===' AS info;
SELECT CONCAT('patients_fictifs : ', COUNT(*), ' enregistrements') AS info FROM patients_fictifs
UNION ALL
SELECT CONCAT('consultations : ', COUNT(*), ' enregistrements') FROM consultations
UNION ALL
SELECT CONCAT('modeles_historique : ', COUNT(*), ' enregistrements') FROM modeles_historique;

SELECT '=== STATISTIQUES CONSULTATIONS ===' AS info;
SELECT 
    scenario,
    COUNT(*) as nb_consultations,
    ROUND(AVG(score_risque), 4) as score_moyen,
    SUM(CASE WHEN niveau_urgence = 'URGENCE' THEN 1 ELSE 0 END) as nb_urgences
FROM consultations
GROUP BY scenario;