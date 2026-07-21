-- ============================================================
-- GROUPE 1 — MODULE 8 (partie 2) : CONCURRENCE A DEUX SESSIONS
-- Scenario : DEUX GUICHETS louent LE DERNIER EXEMPLAIRE au meme
-- instant. Ouvrir DEUX fenetres (2 onglets phpMyAdmin, ou 2
-- terminaux "mysql -u root -p sakila"). Executer les blocs dans
-- l'ordre indique [A1], [B1], [A2], [B2]...
--
-- IMPORTANT (a expliquer au jury) : le trigger du module 7 ne
-- suffit PAS ici. Sous l'isolation REPEATABLE READ, la session B
-- ne "voit" pas l'INSERT non valide de la session A : les deux
-- verifications passent, et la double location est enregistree.
-- La solution est le VERROU (SELECT ... FOR UPDATE) dans une
-- transaction.
-- ============================================================

-- ------------------------------------------------------------
-- PREPARATION (une seule fois, dans n'importe quelle session)
-- ------------------------------------------------------------
USE sakila;
-- Choisir un exemplaire LIBRE qui servira de "dernier exemplaire" :
SELECT i.inventory_id
FROM   inventory i
WHERE  NOT EXISTS (SELECT 1 FROM rental r
                   WHERE r.inventory_id = i.inventory_id
                     AND r.return_date IS NULL)
LIMIT 1;
-- Noter ce numero et REMPLACER 5 par ce numero dans TOUS les
-- blocs ci-dessous si necessaire.

-- ============================================================
-- PHASE 1 : LE PROBLEME (sans protection => double location)
-- ============================================================

-- [A1] --- SESSION A (guichet 1) ---------------------------------
USE sakila;
START TRANSACTION;
-- Verification "naive" : l'exemplaire est-il libre ? (lecture simple)
SELECT COUNT(*) AS deja_sorti FROM rental
WHERE  inventory_id = 5 AND return_date IS NULL;      -- => 0 : libre
-- Le guichetier A enregistre la location (client 1) :
INSERT INTO rental (rental_date, inventory_id, customer_id, staff_id)
VALUES (NOW(), 5, 1, 1);
-- NE PAS ENCORE VALIDER : A discute avec son client...

-- [B1] --- SESSION B (guichet 2), PENDANT ce temps ---------------
USE sakila;
START TRANSACTION;
-- Meme verification naive : B ne voit PAS l'insert non valide de A
SELECT COUNT(*) AS deja_sorti FROM rental
WHERE  inventory_id = 5 AND return_date IS NULL;      -- => 0 aussi !
-- (le trigger fait la meme lecture : il laisse passer, lui aussi)
INSERT INTO rental (rental_date, inventory_id, customer_id, staff_id)
VALUES (NOW(), 5, 2, 2);                              -- client 2

-- [A2] --- SESSION A ----------------------------------------------
COMMIT;

-- [B2] --- SESSION B ----------------------------------------------
COMMIT;

-- [A3] --- N'importe quelle session : CONSTAT DE L'ANOMALIE -------
SELECT rental_id, customer_id, rental_date
FROM   rental
WHERE  inventory_id = 5 AND return_date IS NULL;
-- => DEUX locations actives pour LE MEME exemplaire physique !
--    La donnee est incoherente : c'est le probleme de concurrence.

-- --- NETTOYAGE avant la phase 2 : annuler la double location -----
-- (desactiver un instant le trigger n'est pas necessaire : on
--  supprime simplement les deux lignes fautives)
DELETE FROM rental WHERE inventory_id = 5 AND return_date IS NULL;

-- ============================================================
-- PHASE 2 : LA SOLUTION (transaction + verrou FOR UPDATE)
-- ============================================================

-- [A1'] --- SESSION A ---------------------------------------------
USE sakila;
START TRANSACTION;
-- On VERROUILLE d'abord la ressource disputee (l'exemplaire) :
SELECT inventory_id FROM inventory WHERE inventory_id = 5 FOR UPDATE;
-- Puis verification (lecture verrouillante = elle lit le reel) :
SELECT COUNT(*) AS deja_sorti FROM rental
WHERE  inventory_id = 5 AND return_date IS NULL FOR UPDATE;   -- => 0
-- Libre : A enregistre
INSERT INTO rental (rental_date, inventory_id, customer_id, staff_id)
VALUES (NOW(), 5, 1, 1);
-- (toujours pas de COMMIT : A prend son temps)

-- [B1'] --- SESSION B ---------------------------------------------
USE sakila;
START TRANSACTION;
SELECT inventory_id FROM inventory WHERE inventory_id = 5 FOR UPDATE;
-- ==> B RESTE BLOQUEE ICI : elle ATTEND que A libere le verrou.
--     (montrer au jury la fenetre B qui "tourne")

-- [A2'] --- SESSION A ---------------------------------------------
COMMIT;   -- A valide et libere le verrou

-- [B2'] --- SESSION B (debloquee automatiquement) ------------------
-- La verification s'execute MAINTENANT, apres le COMMIT de A :
SELECT COUNT(*) AS deja_sorti FROM rental
WHERE  inventory_id = 5 AND return_date IS NULL FOR UPDATE;   -- => 1 !
-- L'exemplaire n'est plus libre : le guichet B RENONCE proprement :
ROLLBACK;
-- (et si B s'obstinait a faire l'INSERT, le trigger du module 7,
--  qui lit desormais la location validee de A, le REFUSERAIT et
--  journaliserait la tentative dans audit_location.)

-- [B3'] --- CONSTAT FINAL ------------------------------------------
SELECT rental_id, customer_id FROM rental
WHERE  inventory_id = 5 AND return_date IS NULL;
-- => UNE SEULE location active : l'anomalie a disparu.

-- Nettoyage de fin de demo :
DELETE FROM rental WHERE inventory_id = 5 AND return_date IS NULL;
