-- Convert schema '/data/MyApp/dbicdh/_source/deploy/2/001-auto.yml' to '/data/MyApp/dbicdh/_source/deploy/1/001-auto.yml':;

;
BEGIN;

;
ALTER TABLE classics DROP FOREIGN KEY classics_fk_user_id;

;
DROP TABLE classics;

;

COMMIT;

