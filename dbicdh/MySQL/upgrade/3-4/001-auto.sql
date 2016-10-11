-- Convert schema '/data/MyApp/dbicdh/_source/deploy/3/001-auto.yml' to '/data/MyApp/dbicdh/_source/deploy/4/001-auto.yml':;

;
BEGIN;

;
SET foreign_key_checks=0;

;
CREATE TABLE `authorizer_enterers` (
  `id` char(36) NOT NULL,
  `date_created` datetime NOT NULL,
  `date_updated` datetime NOT NULL,
  `enterer_id` char(36) NOT NULL,
  `authorizer_id` char(36) NOT NULL,
  INDEX `authorizer_enterers_idx_authorizer_id` (`authorizer_id`),
  INDEX `authorizer_enterers_idx_enterer_id` (`enterer_id`),
  INDEX `idx_date_created` (`date_created`),
  INDEX `idx_date_updated` (`date_updated`),
  PRIMARY KEY (`id`),
  CONSTRAINT `authorizer_enterers_fk_authorizer_id` FOREIGN KEY (`authorizer_id`) REFERENCES `users` (`id`) ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT `authorizer_enterers_fk_enterer_id` FOREIGN KEY (`enterer_id`) REFERENCES `users` (`id`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARACTER SET utf8 COLLATE utf8_unicode_ci;

;
CREATE TABLE `pbdb`.`session_data` (
  `id` char(36) NOT NULL,
  `date_created` datetime NOT NULL,
  `date_updated` datetime NOT NULL,
  INDEX `idx_date_created` (`date_created`),
  INDEX `idx_date_updated` (`date_updated`),
  PRIMARY KEY (`id`)
) DEFAULT CHARACTER SET utf8 COLLATE utf8_unicode_ci;

;
SET foreign_key_checks=1;

;

COMMIT;

