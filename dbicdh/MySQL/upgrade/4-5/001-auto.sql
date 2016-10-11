-- Convert schema '/data/MyApp/dbicdh/_source/deploy/4/001-auto.yml' to '/data/MyApp/dbicdh/_source/deploy/5/001-auto.yml':;

;
BEGIN;

;
SET foreign_key_checks=0;

;
CREATE TABLE `authents` (
  `id` char(36) NOT NULL,
  `date_created` datetime NOT NULL,
  `date_updated` datetime NOT NULL,
  `enterer_no` integer NOT NULL,
  `authorizer_no` integer NOT NULL,
  INDEX `idx_date_created` (`date_created`),
  INDEX `idx_date_updated` (`date_updated`),
  PRIMARY KEY (`id`)
) DEFAULT CHARACTER SET utf8 COLLATE utf8_unicode_ci;

;
SET foreign_key_checks=1;

;
ALTER TABLE users ADD COLUMN authorizer_no integer NULL,
                  ADD INDEX idx_person_no (person_no);

;

COMMIT;

