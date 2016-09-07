-- 
-- Created by SQL::Translator::Producer::MySQL
-- Created on Thu Aug 18 17:17:54 2016
-- 
;
SET foreign_key_checks=0;
--
-- Table: `trends_logs`
--
CREATE TABLE `trends_logs` (
  `id` char(36) NOT NULL,
  `date_created` datetime NOT NULL,
  `date_updated` datetime NOT NULL,
  `value` float(15, 2) NOT NULL,
  `name` varchar(60) NOT NULL,
  `note` text NULL,
  INDEX `idx_date_name_value` (`date_created`, `name`, `value`),
  INDEX `idx_name` (`name`),
  PRIMARY KEY (`id`)
);
--
-- Table: `trends_logs_daily`
--
CREATE TABLE `trends_logs_daily` (
  `id` char(36) NOT NULL,
  `date_created` datetime NOT NULL,
  `date_updated` datetime NOT NULL,
  `value` float(15, 2) NOT NULL,
  `name` varchar(60) NOT NULL,
  `day` datetime NOT NULL,
  INDEX `idx_date_name_value` (`day`, `name`, `value`),
  INDEX `idx_name_date` (`name`, `day`),
  INDEX `idx_name` (`name`),
  PRIMARY KEY (`id`)
);
--
-- Table: `trends_logs_hourly`
--
CREATE TABLE `trends_logs_hourly` (
  `id` char(36) NOT NULL,
  `date_created` datetime NOT NULL,
  `date_updated` datetime NOT NULL,
  `value` float(15, 2) NOT NULL,
  `name` varchar(60) NOT NULL,
  `hour` datetime NOT NULL,
  INDEX `idx_date_name_value` (`hour`, `name`, `value`),
  INDEX `idx_name_date` (`name`, `hour`),
  INDEX `idx_name` (`name`),
  PRIMARY KEY (`id`)
);
--
-- Table: `trends_logs_monthly`
--
CREATE TABLE `trends_logs_monthly` (
  `id` char(36) NOT NULL,
  `date_created` datetime NOT NULL,
  `date_updated` datetime NOT NULL,
  `value` float(15, 2) NOT NULL,
  `name` varchar(60) NOT NULL,
  `month` datetime NOT NULL,
  INDEX `idx_date_name_value` (`month`, `name`, `value`),
  INDEX `idx_name_date` (`name`, `month`),
  INDEX `idx_name` (`name`),
  PRIMARY KEY (`id`)
);
--
-- Table: `trends_logs_yearly`
--
CREATE TABLE `trends_logs_yearly` (
  `id` char(36) NOT NULL,
  `date_created` datetime NOT NULL,
  `date_updated` datetime NOT NULL,
  `value` float(15, 2) NOT NULL,
  `name` varchar(60) NOT NULL,
  `year` datetime NOT NULL,
  INDEX `idx_date_name_value` (`year`, `name`, `value`),
  INDEX `idx_name_date` (`name`, `year`),
  INDEX `idx_name` (`name`),
  PRIMARY KEY (`id`)
);
--
-- Table: `trendsreports`
--
CREATE TABLE `trendsreports` (
  `id` char(36) NOT NULL,
  `date_created` datetime NOT NULL,
  `date_updated` datetime NOT NULL,
  `name` varchar(60) NOT NULL,
  `fields` mediumblob NULL,
  INDEX `idx_date_created` (`date_created`),
  INDEX `idx_date_updated` (`date_updated`),
  PRIMARY KEY (`id`)
) DEFAULT CHARACTER SET utf8 COLLATE utf8_unicode_ci;
--
-- Table: `users`
--
CREATE TABLE `users` (
  `id` char(36) NOT NULL,
  `date_created` datetime NOT NULL,
  `date_updated` datetime NOT NULL,
  `admin` tinyint NOT NULL DEFAULT 0,
  `real_name` varchar(255) NULL DEFAULT '',
  `password_type` varchar(10) NOT NULL DEFAULT 'bcrypt',
  `password_salt` char(16) NOT NULL DEFAULT 'abcdefghijklmnop',
  `username` varchar(30) NOT NULL,
  `email` varchar(255) NULL,
  `password` char(50) NULL,
  `use_as_display_name` varchar(10) NULL DEFAULT 'username',
  `developer` tinyint NOT NULL DEFAULT 0,
  `last_login` datetime NOT NULL,
  INDEX `idx_search` (`real_name`, `username`, `email`),
  PRIMARY KEY (`id`),
  UNIQUE `users_email` (`email`),
  UNIQUE `users_username` (`username`)
) ENGINE=InnoDB;
--
-- Table: `api_keys`
--
CREATE TABLE `api_keys` (
  `id` char(36) NOT NULL,
  `date_created` datetime NOT NULL,
  `date_updated` datetime NOT NULL,
  `private_key` char(36) NULL,
  `reason` varchar(255) NULL,
  `name` varchar(30) NOT NULL,
  `uri` varchar(255) NULL,
  `user_id` char(36) NOT NULL,
  INDEX `api_keys_idx_user_id` (`user_id`),
  INDEX `idx_date_created` (`date_created`),
  INDEX `idx_date_updated` (`date_updated`),
  PRIMARY KEY (`id`),
  UNIQUE `api_keys_name` (`name`),
  CONSTRAINT `api_keys_fk_user_id` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARACTER SET utf8 COLLATE utf8_unicode_ci;
--
-- Table: `api_key_permissions`
--
CREATE TABLE `api_key_permissions` (
  `id` char(36) NOT NULL,
  `date_created` datetime NOT NULL,
  `date_updated` datetime NOT NULL,
  `permission` varchar(30) NOT NULL,
  `api_key_id` char(36) NOT NULL,
  `user_id` char(36) NOT NULL,
  INDEX `api_key_permissions_idx_api_key_id` (`api_key_id`),
  INDEX `api_key_permissions_idx_user_id` (`user_id`),
  INDEX `idx_date_created` (`date_created`),
  INDEX `idx_date_updated` (`date_updated`),
  INDEX `idx_apikey_user` (`api_key_id`, `user_id`),
  PRIMARY KEY (`id`),
  CONSTRAINT `api_key_permissions_fk_api_key_id` FOREIGN KEY (`api_key_id`) REFERENCES `api_keys` (`id`) ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT `api_key_permissions_fk_user_id` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARACTER SET utf8 COLLATE utf8_unicode_ci;
SET foreign_key_checks=1;
