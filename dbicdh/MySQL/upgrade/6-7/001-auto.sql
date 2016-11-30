-- Convert schema '/data/MyApp/dbicdh/_source/deploy/6/001-auto.yml' to '/data/MyApp/dbicdh/_source/deploy/7/001-auto.yml':;

;
BEGIN;

;
ALTER TABLE users ADD COLUMN orcid varchar(19) NOT NULL;

;

COMMIT;

