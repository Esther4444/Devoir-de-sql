-- ============================================================
-- GROUPE 1 — MODULE 8 (partie 1) : TRANSACTION METIER
-- "Tout ou rien" : location + paiement dans UNE transaction.
-- Prerequis : 01_installation.sql execute.
-- ============================================================
USE sakila;

-- Etat AVANT : compter les lignes
SELECT (SELECT COUNT(*) FROM rental)  AS nb_locations,
       (SELECT COUNT(*) FROM payment) AS nb_paiements;

-- ------------------------------------------------------------
-- CAS 1 : tout se passe bien => COMMIT
-- ------------------------------------------------------------
CALL louer_et_encaisser(148, 2, 1, 1);   -- client 148, film 2 (ACE GOLDFINGER)

-- Les DEUX ecritures ont eu lieu ensemble :
SELECT (SELECT COUNT(*) FROM rental)  AS nb_locations,
       (SELECT COUNT(*) FROM payment) AS nb_paiements;

-- ------------------------------------------------------------
-- CAS 2 : une etape echoue => ROLLBACK automatique
-- ------------------------------------------------------------
-- Film sans stock => la transaction est ANNULEE en entier :
CALL louer_et_encaisser(148, 802, 1, 1);
-- ERREUR attendue : "Transaction annulee : aucun exemplaire disponible"

-- Preuve du "tout ou rien" : AUCUNE ligne ajoutee, ni location
-- ni paiement orphelin :
SELECT (SELECT COUNT(*) FROM rental)  AS nb_locations,
       (SELECT COUNT(*) FROM payment) AS nb_paiements;

-- ------------------------------------------------------------
-- ACID en une phrase chacune (a dire a l'oral) :
-- A - Atomicite   : la location et le paiement reussissent ou
--                   echouent ENSEMBLE, jamais a moitie.
-- C - Coherence   : la base passe d'un etat valide a un autre
--                   etat valide (pas de paiement sans location).
-- I - Isolation   : deux guichets simultanes ne voient pas les
--                   operations inachevees l'un de l'autre.
-- D - Durabilite  : apres COMMIT, la location survit meme a une
--                   coupure de courant.
-- ------------------------------------------------------------
