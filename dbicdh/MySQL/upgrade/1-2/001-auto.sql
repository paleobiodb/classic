-- Convert schema '/data/MyApp/dbicdh/_source/deploy/1/001-auto.yml' to '/data/MyApp/dbicdh/_source/deploy/2/001-auto.yml':;

;
BEGIN;

;
SET foreign_key_checks=0;

;
CREATE TABLE `classics` (
  `id` char(36) NOT NULL,
  `date_created` datetime NOT NULL,
  `date_updated` datetime NOT NULL,
  `is_cool` tinyint NOT NULL DEFAULT 0,
  `status` varchar(60) NOT NULL DEFAULT 'pending',
  `name` varchar(60) NOT NULL,
  `description` mediumtext NOT NULL,
  `end_date` datetime NOT NULL,
  `start_date` datetime NOT NULL,
  `user_id` char(36) NOT NULL,
  `uri_part` varchar(60) NOT NULL,
  INDEX `classics_idx_user_id` (`user_id`),
  INDEX `idx_date_created` (`date_created`),
  INDEX `idx_date_updated` (`date_updated`),
  PRIMARY KEY (`id`),
  UNIQUE `classics_uri_part` (`uri_part`),
  CONSTRAINT `classics_fk_user_id` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`)
) ENGINE=InnoDB DEFAULT CHARACTER SET utf8 COLLATE utf8_unicode_ci;

;
SET foreign_key_checks=1;

;

COMMIT;

