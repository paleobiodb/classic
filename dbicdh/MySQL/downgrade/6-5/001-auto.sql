-- Convert schema '/data/MyApp/dbicdh/_source/deploy/6/001-auto.yml' to '/data/MyApp/dbicdh/_source/deploy/5/001-auto.yml':;

;
BEGIN;

;
ALTER TABLE authents DROP INDEX authents_enterer_no_authorizer_no,
                     DROP FOREIGN KEY authents_fk_authorizer_no,
                     DROP FOREIGN KEY authents_fk_enterer_no,
                     DROP INDEX authents_idx_authorizer_no,
                     DROP INDEX authents_idx_enterer_no,
                     DEFAULT CHARACTER SET utf8 COLLATE utf8_unicode_ci;

;

COMMIT;

