-- Convert schema '/data/MyApp/dbicdh/_source/deploy/2/001-auto.yml' to '/data/MyApp/dbicdh/_source/deploy/3/001-auto.yml':;

;
BEGIN;

;
ALTER TABLE users ADD COLUMN country char(2) NOT NULL,
                  ADD COLUMN person_no integer NULL,
                  ADD COLUMN middle_name varchar(80) NOT NULL,
                  ADD COLUMN role varchar(80) NOT NULL,
                  ADD COLUMN institution varchar(80) NOT NULL,
                  ADD COLUMN last_name varchar(80) NOT NULL,
                  ADD COLUMN first_name varchar(80) NOT NULL,
                  ADD INDEX idx_country (country),
                  ADD INDEX idx_last_name (last_name);

;

COMMIT;

