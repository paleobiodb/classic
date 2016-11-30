-- Convert schema '/data/MyApp/dbicdh/_source/deploy/8/001-auto.yml' to '/data/MyApp/dbicdh/_source/deploy/7/001-auto.yml':;

;
BEGIN;

;
ALTER TABLE users DROP COLUMN contributor_status,
                  CHANGE COLUMN role role varchar(80) NOT NULL;

;

COMMIT;

