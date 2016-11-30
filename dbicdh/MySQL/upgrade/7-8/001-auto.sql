-- Convert schema '/data/MyApp/dbicdh/_source/deploy/7/001-auto.yml' to '/data/MyApp/dbicdh/_source/deploy/8/001-auto.yml':;

;
BEGIN;

;
ALTER TABLE users ADD COLUMN contributor_status enum("active", "disabled", "deceased") NOT NULL,
                  CHANGE COLUMN role role enum("guest", "authorizer", "enterer", "student") NOT NULL;

;

COMMIT;

