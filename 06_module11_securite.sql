-- ============================================================
-- GROUPE 1 — MODULE 11 : SECURITE ET ADMINISTRATION
-- Utilisateur restreint "guichet" + sauvegarde / restauration.
-- Prerequis : 01_installation.sql (l'utilisateur y est cree).
-- ============================================================

-- ------------------------------------------------------------
-- PARTIE A — VERIFIER LES DROITS (en tant qu'ADMIN)
-- ------------------------------------------------------------
SHOW GRANTS FOR 'guichet'@'localhost';
-- Attendu : SELECT sur les 2 vues, EXECUTE sur la procedure,
-- et RIEN d'autre. C'est le principe du MOINDRE PRIVILEGE.

-- ------------------------------------------------------------
-- PARTIE B — DEMONSTRATION EN TANT QUE "guichet"
-- ------------------------------------------------------------
-- Se connecter dans une AUTRE session :
--   Terminal    : mysql -u guichet -p        (mdp : Guichet#2026!)
--   phpMyAdmin  : se deconnecter puis se connecter en "guichet"
-- Puis executer :

-- B1. La vue FONCTIONNE (mais sans email, adresse, montants) :
SELECT * FROM sakila.v_locations_en_cours LIMIT 5;
SELECT * FROM sakila.v_historique_locations LIMIT 5;

-- B2. L'acces aux TABLES DE BASE est REFUSE :
SELECT * FROM sakila.customer;
-- ERREUR attendue : SELECT command denied to user 'guichet'@...

SELECT * FROM sakila.rental;
-- ERREUR attendue : SELECT command denied

-- B3. Toute ECRITURE directe est REFUSEE :
DELETE FROM sakila.rental WHERE rental_id = 1;
-- ERREUR attendue : DELETE command denied

UPDATE sakila.customer SET first_name = 'X' WHERE customer_id = 1;
-- ERREUR attendue : UPDATE command denied

-- B4. Mais le guichetier PEUT enregistrer une location, car il
-- passe par la PROCEDURE (execution avec les droits du createur) :
CALL sakila.enregistrer_location(148, 3, 1, 1);
-- => la seule voie d'ecriture autorisee, controlee et auditee.

-- ------------------------------------------------------------
-- PARTIE C — SAUVEGARDE / PERTE / RESTAURATION (en ADMIN)
-- ------------------------------------------------------------
-- C1. SAUVEGARDE (a lancer dans un terminal Windows/Linux,
--     PAS dans phpMyAdmin) :
--
--   mysqldump -u root -p --routines --triggers sakila > sakila_sauvegarde.sql
--
--   (--routines : inclut les procedures ; --triggers : les triggers.
--    Alternative phpMyAdmin : onglet Exporter > methode
--    personnalisee > cocher "Procedures et fonctions" et "Triggers".)

-- C2. RELEVER L'ETAT DE REFERENCE avant le sinistre :
SELECT COUNT(*) AS nb_paiements_avant FROM sakila.payment;   -- ex. 16049

-- C3. SIMULER LA PERTE DE DONNEES (le "sinistre") :
DELETE FROM sakila.payment;
SELECT COUNT(*) AS nb_paiements_apres_sinistre FROM sakila.payment;  -- 0 !

-- C4. RESTAURER (terminal) :
--
--   mysql -u root -p sakila < sakila_sauvegarde.sql
--
--   (Alternative phpMyAdmin : onglet Importer > choisir le fichier.)

-- C5. VERIFIER que l'etat initial est retabli :
SELECT COUNT(*) AS nb_paiements_restaures FROM sakila.payment;  -- retour a la valeur de C2
SELECT * FROM sakila.v_locations_en_cours LIMIT 3;              -- les vues fonctionnent

-- ------------------------------------------------------------
-- MATRICE DES DROITS (a mettre dans le dossier)
-- ------------------------------------------------------------
-- | Objet                    | root (admin) | guichet          |
-- |--------------------------|--------------|------------------|
-- | Tables rental/customer.. | Tous droits  | AUCUN acces      |
-- | v_locations_en_cours     | Tous droits  | SELECT seulement |
-- | v_historique_locations   | Tous droits  | SELECT seulement |
-- | enregistrer_location     | Tous droits  | EXECUTE seulement|
-- | louer_et_encaisser       | Tous droits  | AUCUN acces      |
-- | DELETE / UPDATE / DROP   | Oui          | NON (refuse)     |
-- | Donnees sensibles (email,|              |                  |
-- | adresse, montants)       | Visibles     | JAMAIS visibles  |
