-- Convert schema '/data/MyApp/dbicdh/_source/deploy/5/001-auto.yml' to '/data/MyApp/dbicdh/_source/deploy/4/001-auto.yml':;

;
BEGIN;

;
ALTER TABLE users DROP INDEX idx_person_no,
                  DROP COLUMN authorizer_no;

;
DROP TABLE authents;

;

COMMIT;

