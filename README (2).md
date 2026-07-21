# Devoir de SQL — Groupe 1 : Location de films (Sakila)

Projet de base de données réalisé sur la base **Sakila** (MySQL / MariaDB), thème **location de films** (tables `rental`, `inventory`, `customer`, `film`).

**Soutenance :** 23 juillet 2026
**Membres :** Esther Lydie · Jude · Lidvige Johanne · Melchior Junior · Oniandji · Terrence · Kerane
**Encadrant :** Prime Clet ESSE ESSE

## Contenu du dépôt

- `07_dossier_resume.pdf` — dossier résumé complet (présentation du thème, explication des modules 7, 8, 9, 11, tableau de mesures, matrice des droits).
- `sql/01_installation.sql` — script d'installation complet : table d'audit, vues, procédures stockées, triggers, index composite, utilisateur restreint `guichet`. **À exécuter en premier**, sur une base Sakila neuve.
- `sql/02_module7_demo.sql` — démonstration Module 7 (vues, procédure `enregistrer_location`, trigger bloquant + audit).
- `sql/03_module8_transaction.sql` — démonstration Module 8 : transaction métier « tout ou rien » (`louer_et_encaisser`), ACID.
- `sql/04_module8_concurrence.sql` — démonstration Module 8 : concurrence à deux sessions (problème puis solution avec `SELECT ... FOR UPDATE`).
- `sql/05_module9_indexation.sql` — protocole complet de mesure avant/après indexation (Module 9).
- `sql/06_module11_securite.sql` — démonstration Module 11 : droits de l'utilisateur `guichet`, sauvegarde/restauration.

## Ordre d'exécution

1. Importer le schéma **Sakila** officiel dans une base neuve.
2. Exécuter `sql/01_installation.sql` (rejouable, nettoyage automatique en tête).
3. Dérouler les scripts de démonstration dans l'ordre (`02` → `06`) pour la soutenance.

## Thème du fil conducteur

La question centrale qui traverse les quatre modules : **« cet exemplaire est-il disponible ? »**
- Les **vues** l'affichent.
- Le **trigger** la protège contre les erreurs.
- La **transaction avec verrou** la protège contre la concurrence.
- L'**index composite** la rend instantanée à vérifier.
- La **politique de droits** garantit que seuls les canaux prévus peuvent la modifier.
