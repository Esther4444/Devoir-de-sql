-- ============================================================
-- PROJET BASES DE DONNEES — GROUPE 1 : LOCATION DE FILMS
-- Tables principales : rental, inventory, customer, film
-- Fichier : 01_installation.sql
-- A executer sur une base Sakila NEUVE (MySQL / MariaDB).
-- Cree : table d'audit, vues, procedures stockees, triggers,
--        index composite et utilisateur restreint "guichet".
-- Le script est RE-EXECUTABLE (nettoyage en tete).
-- phpMyAdmin : coller tel quel dans l'onglet SQL (les lignes
-- DELIMITER sont comprises par phpMyAdmin).
-- ============================================================

USE sakila;

-- ------------------------------------------------------------
-- 0. NETTOYAGE (permet de rejouer le script sans erreur)
-- ------------------------------------------------------------
DROP TRIGGER   IF EXISTS trg_bloque_double_location;
DROP TRIGGER   IF EXISTS trg_audit_location_ok;
DROP PROCEDURE IF EXISTS enregistrer_location;
DROP PROCEDURE IF EXISTS louer_et_encaisser;
DROP VIEW      IF EXISTS v_locations_en_cours;
DROP VIEW      IF EXISTS v_historique_locations;
DROP TABLE     IF EXISTS audit_location;
DROP USER      IF EXISTS 'guichet'@'localhost';

-- ------------------------------------------------------------
-- 1. TABLE D'AUDIT (Module 7)
-- ------------------------------------------------------------
-- POURQUOI ENGINE=MyISAM ? MyISAM est NON transactionnel :
-- quand le trigger refuse une location (SIGNAL), l'INSERT fautif
-- est annule, mais la ligne d'audit ecrite par le trigger
-- SURVIT a cette annulation. Avec InnoDB, elle serait annulee
-- en meme temps que l'instruction refusee.
CREATE TABLE audit_location (
    audit_id     INT AUTO_INCREMENT PRIMARY KEY,
    action       VARCHAR(30)  NOT NULL,           -- LOCATION_OK / LOCATION_REFUSEE
    inventory_id INT          NULL,
    customer_id  INT          NULL,
    utilisateur  VARCHAR(100) NOT NULL,           -- qui a fait l'action (CURRENT_USER)
    date_action  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    message      VARCHAR(255) NULL
) ENGINE = MyISAM
  COMMENT = 'Journal des locations : tentatives refusees et locations validees';

-- ------------------------------------------------------------
-- 2. VUES (Module 7)
-- ------------------------------------------------------------

-- Vue 1 : LOCATIONS EN COURS (exemplaires non rendus).
-- Vue "metier" du guichetier : quel film, quel client, quel
-- magasin, date de retour prevue (calculee avec rental_duration).
CREATE VIEW v_locations_en_cours AS
SELECT  r.rental_id,
        r.rental_date                                            AS date_location,
        DATE_ADD(r.rental_date, INTERVAL f.rental_duration DAY)  AS retour_prevu,
        f.title                                                  AS film,
        i.store_id                                               AS magasin,
        CONCAT(c.first_name, ' ', c.last_name)                   AS client
FROM    rental    r
JOIN    inventory i ON i.inventory_id = r.inventory_id
JOIN    film      f ON f.film_id      = i.film_id
JOIN    customer  c ON c.customer_id  = r.customer_id
WHERE   r.return_date IS NULL;

-- Vue 2 : HISTORIQUE LOCATION + CLIENT + FILM — VUE DE SECURITE.
-- Colonnes sensibles volontairement MASQUEES : ni email, ni
-- adresse du client, ni montants. C'est la SEULE porte d'entree
-- de l'utilisateur restreint "guichet" (Module 11).
CREATE VIEW v_historique_locations AS
SELECT  r.rental_id,
        r.rental_date  AS date_location,
        r.return_date  AS date_retour,
        f.title        AS film,
        f.rating       AS classification,
        CONCAT(c.first_name, ' ', c.last_name) AS client,
        i.store_id     AS magasin
FROM    rental    r
JOIN    inventory i ON i.inventory_id = r.inventory_id
JOIN    film      f ON f.film_id      = i.film_id
JOIN    customer  c ON c.customer_id  = r.customer_id;

-- ------------------------------------------------------------
-- 3. PROCEDURE STOCKEE : enregistrer_location (Module 7)
-- ------------------------------------------------------------
-- Recoit des parametres, VERIFIE des conditions (client actif,
-- exemplaire disponible), CALCULE la date de retour prevue,
-- puis ECRIT dans rental. Verrouille l'exemplaire choisi
-- (FOR UPDATE) pour resister a la concurrence (lien Module 8).
DELIMITER $$
CREATE PROCEDURE enregistrer_location(
    IN p_customer_id SMALLINT UNSIGNED,   -- le client
    IN p_film_id     SMALLINT UNSIGNED,   -- le film souhaite
    IN p_store_id    TINYINT  UNSIGNED,   -- le magasin
    IN p_staff_id    TINYINT  UNSIGNED    -- l'employe au guichet
)
BEGIN
    DECLARE v_inventory_id INT DEFAULT NULL;
    DECLARE v_duree        INT DEFAULT NULL;
    DECLARE v_actif        INT DEFAULT 0;

    -- Verification 1 : le client existe et est actif
    SELECT COUNT(*) INTO v_actif
    FROM   customer
    WHERE  customer_id = p_customer_id AND active = 1;

    IF v_actif = 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Client inconnu ou inactif : location refusee';
    END IF;

    -- Verification 2 : chercher UN exemplaire libre de ce film
    -- dans ce magasin, et le VERROUILLER (FOR UPDATE)
    SELECT i.inventory_id, f.rental_duration
    INTO   v_inventory_id, v_duree
    FROM   inventory i
    JOIN   film f ON f.film_id = i.film_id
    WHERE  i.film_id  = p_film_id
      AND  i.store_id = p_store_id
      AND  NOT EXISTS (SELECT 1 FROM rental r
                       WHERE r.inventory_id = i.inventory_id
                         AND r.return_date IS NULL)
    LIMIT 1
    FOR UPDATE;

    IF v_inventory_id IS NULL THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Aucun exemplaire disponible pour ce film dans ce magasin';
    END IF;

    -- Ecriture : la location est enregistree
    INSERT INTO rental (rental_date, inventory_id, customer_id, staff_id)
    VALUES (NOW(), v_inventory_id, p_customer_id, p_staff_id);

    -- Calcul restitue a l'appelant : date de retour prevue
    SELECT LAST_INSERT_ID()                        AS rental_id,
           v_inventory_id                          AS exemplaire,
           DATE_ADD(NOW(), INTERVAL v_duree DAY)   AS retour_prevu;
END$$
DELIMITER ;

-- ------------------------------------------------------------
-- 4. TRIGGERS (Module 7)
-- ------------------------------------------------------------

-- Trigger 1 : BLOQUE l'incoherence metier — on ne peut pas louer
-- un exemplaire deja sorti (return_date IS NULL). La tentative
-- est journalisee AVANT le refus ; grace a MyISAM, la ligne
-- d'audit survit a l'annulation de l'INSERT fautif.
DELIMITER $$
CREATE TRIGGER trg_bloque_double_location
BEFORE INSERT ON rental
FOR EACH ROW
BEGIN
    DECLARE v_nb INT;

    SELECT COUNT(*) INTO v_nb
    FROM   rental
    WHERE  inventory_id = NEW.inventory_id
      AND  return_date IS NULL;

    IF v_nb > 0 THEN
        INSERT INTO audit_location (action, inventory_id, customer_id, utilisateur, message)
        VALUES ('LOCATION_REFUSEE', NEW.inventory_id, NEW.customer_id,
                CURRENT_USER(), 'Tentative de louer un exemplaire deja sorti');

        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'REFUSE : cet exemplaire est deja en location';
    END IF;
END$$

-- Trigger 2 : journalise chaque location VALIDEE (piste d'audit).
CREATE TRIGGER trg_audit_location_ok
AFTER INSERT ON rental
FOR EACH ROW
BEGIN
    INSERT INTO audit_location (action, inventory_id, customer_id, utilisateur, message)
    VALUES ('LOCATION_OK', NEW.inventory_id, NEW.customer_id,
            CURRENT_USER(), CONCAT('Location enregistree, rental_id=', NEW.rental_id));
END$$
DELIMITER ;

-- ------------------------------------------------------------
-- 5. PROCEDURE TRANSACTIONNELLE : louer_et_encaisser (Module 8)
-- ------------------------------------------------------------
-- Transaction METIER "tout ou rien" : la location ET son paiement
-- sont enregistres ensemble. Si UNE etape echoue, le HANDLER fait
-- ROLLBACK : la base reste coherente (Atomicite du A de ACID).
DELIMITER $$
CREATE PROCEDURE louer_et_encaisser(
    IN p_customer_id SMALLINT UNSIGNED,
    IN p_film_id     SMALLINT UNSIGNED,
    IN p_store_id    TINYINT  UNSIGNED,
    IN p_staff_id    TINYINT  UNSIGNED
)
BEGIN
    DECLARE v_inventory_id INT           DEFAULT NULL;
    DECLARE v_tarif        DECIMAL(4,2)  DEFAULT NULL;
    DECLARE v_rental_id    INT           DEFAULT NULL;

    -- En cas d'erreur SQL n'importe ou : tout est annule
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;   -- on remonte l'erreur d'origine a l'appelant
    END;

    START TRANSACTION;

        -- Choisir et verrouiller un exemplaire libre
        SELECT i.inventory_id, f.rental_rate
        INTO   v_inventory_id, v_tarif
        FROM   inventory i
        JOIN   film f ON f.film_id = i.film_id
        WHERE  i.film_id  = p_film_id
          AND  i.store_id = p_store_id
          AND  NOT EXISTS (SELECT 1 FROM rental r
                           WHERE r.inventory_id = i.inventory_id
                             AND r.return_date IS NULL)
        LIMIT 1
        FOR UPDATE;

        IF v_inventory_id IS NULL THEN
            SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Transaction annulee : aucun exemplaire disponible';
        END IF;

        -- Ecriture 1 : la location
        INSERT INTO rental (rental_date, inventory_id, customer_id, staff_id)
        VALUES (NOW(), v_inventory_id, p_customer_id, p_staff_id);
        SET v_rental_id = LAST_INSERT_ID();

        -- Ecriture 2 : le paiement associe
        INSERT INTO payment (customer_id, staff_id, rental_id, amount, payment_date)
        VALUES (p_customer_id, p_staff_id, v_rental_id, v_tarif, NOW());

    COMMIT;

    SELECT v_rental_id AS rental_id, v_tarif AS montant_encaisse,
           'Location + paiement valides ensemble (COMMIT)' AS statut;
END$$
DELIMITER ;

-- ------------------------------------------------------------
-- 6. INDEX (Module 9) — etat FINAL apres optimisation
-- ------------------------------------------------------------
-- NB : Sakila livre deja idx_fk_customer_id sur rental(customer_id).
-- Notre apport est l'index COMPOSITE ci-dessous : il accelere la
-- question centrale du theme "cet exemplaire est-il sorti ?"
-- (WHERE inventory_id = ? AND return_date IS NULL), utilisee par
-- le trigger, la procedure et la vue des locations en cours.
-- Le protocole complet de mesure avant/apres est dans
-- 05_module9_indexation.sql.
CREATE INDEX idx_loc_inventaire_retour ON rental (inventory_id, return_date);

-- ------------------------------------------------------------
-- 7. UTILISATEUR RESTREINT "guichet" (Module 11)
-- ------------------------------------------------------------
-- Principe du MOINDRE PRIVILEGE : le guichetier
--   - LIT les deux vues (jamais les tables de base),
--   - EXECUTE la procedure d'enregistrement,
--   - et RIEN d'autre (aucun DELETE, UPDATE, ni SELECT sur customer).
-- Les vues etant en SQL SECURITY DEFINER (defaut), "guichet"
-- accede aux donnees A TRAVERS elles sans aucun droit direct
-- sur rental/customer/film/inventory.
CREATE USER 'guichet'@'localhost' IDENTIFIED BY 'Guichet#2026!';

GRANT SELECT  ON sakila.v_locations_en_cours   TO 'guichet'@'localhost';
GRANT SELECT  ON sakila.v_historique_locations TO 'guichet'@'localhost';
GRANT EXECUTE ON PROCEDURE sakila.enregistrer_location TO 'guichet'@'localhost';

FLUSH PRIVILEGES;

-- ------------------------------------------------------------
-- FIN — Verification rapide de l'installation
-- ------------------------------------------------------------
SELECT 'Installation terminee' AS statut;
SHOW TRIGGERS LIKE 'rental';
SELECT COUNT(*) AS locations_en_cours FROM v_locations_en_cours;
