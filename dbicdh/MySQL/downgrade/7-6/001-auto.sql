-- Convert schema '/data/MyApp/dbicdh/_source/deploy/7/001-auto.yml' to '/data/MyApp/dbicdh/_source/deploy/6/001-auto.yml':;

;
BEGIN;

;
ALTER TABLE users DROP COLUMN orcid;

;

COMMIT;

