-- Convert schema '/data/MyApp/dbicdh/_source/deploy/3/001-auto.yml' to '/data/MyApp/dbicdh/_source/deploy/2/001-auto.yml':;

;
BEGIN;

;
ALTER TABLE users DROP INDEX idx_country,
                  DROP INDEX idx_last_name,
                  DROP COLUMN country,
                  DROP COLUMN person_no,
                  DROP COLUMN middle_name,
                  DROP COLUMN role,
                  DROP COLUMN institution,
                  DROP COLUMN last_name,
                  DROP COLUMN first_name;

;

COMMIT;

