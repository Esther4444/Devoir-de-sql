-- ============================================================
-- GROUPE 1 — MODULE 7 : DEMONSTRATION EN DIRECT
-- Vues, procedure stockee, trigger bloquant + audit
-- Prerequis : 01_installation.sql execute.
-- Derouler bloc par bloc devant le jury.
-- ============================================================
USE sakila;

-- ------------------------------------------------------------
-- DEMO 1 : LES VUES
-- ------------------------------------------------------------

-- 1a. Locations en cours (avec date de retour prevue calculee)
SELECT * FROM v_locations_en_cours LIMIT 10;

-- 1b. Vue de securite : historique complet SANS email, SANS
--     adresse, SANS montants. Comparer avec la table brute :
SELECT rental_id, date_location, film, client FROM v_historique_locations LIMIT 5;
-- (en tant qu'admin seulement, pour montrer ce que la vue CACHE :)
SELECT customer_id, first_name, last_name, email FROM customer LIMIT 3;

-- ------------------------------------------------------------
-- DEMO 2 : LA PROCEDURE enregistrer_location
-- ------------------------------------------------------------
-- Le client 148 (le plus actif de Sakila) loue le film 1
-- (ACADEMY DINOSAUR) au magasin 1, guichetier n°1.
CALL enregistrer_location(148, 1, 1, 1);
-- => renvoie rental_id, l'exemplaire choisi et le retour prevu.

-- La location apparait immediatement dans la vue :
SELECT * FROM v_locations_en_cours WHERE client = 'ELEANOR HUNT';

-- Cas limite 1 : client inexistant => la procedure REFUSE
CALL enregistrer_location(9999, 1, 1, 1);
-- ERREUR attendue : "Client inconnu ou inactif : location refusee"

-- Cas limite 2 : film sans exemplaire disponible dans ce magasin
-- (le film 802 'SLEEPWALKERS ATTITUDE' n'est en stock nulle part... 
--  utiliser la requete ci-dessous pour trouver un cas chez vous)
SELECT f.film_id, f.title
FROM   film f
WHERE  NOT EXISTS (SELECT 1 FROM inventory i WHERE i.film_id = f.film_id)
LIMIT 3;
-- puis :
CALL enregistrer_location(148, /* film_id trouve */ 802, 1, 1);
-- ERREUR attendue : "Aucun exemplaire disponible..."

-- ------------------------------------------------------------
-- DEMO 3 : LE TRIGGER BLOQUANT + AUDIT (le moment cle)
-- ------------------------------------------------------------

-- Etape 1 : trouver un exemplaire ACTUELLEMENT SORTI
SET @inv_sorti := (SELECT inventory_id FROM rental
                   WHERE return_date IS NULL LIMIT 1);
SELECT @inv_sorti AS exemplaire_deja_sorti;

-- Etape 2 : TENTER L'ACTION INTERDITE devant le jury —
-- louer cet exemplaire une seconde fois :
INSERT INTO rental (rental_date, inventory_id, customer_id, staff_id)
VALUES (NOW(), @inv_sorti, 148, 1);
-- ERREUR attendue : "REFUSE : cet exemplaire est deja en location"

-- Etape 3 : la table d'audit s'est remplie SOUS LES YEUX du jury
SELECT * FROM audit_location ORDER BY audit_id DESC LIMIT 5;
-- On y voit : la LOCATION_REFUSEE (tentative bloquee) et,
-- plus haut, les LOCATION_OK des demonstrations precedentes.
