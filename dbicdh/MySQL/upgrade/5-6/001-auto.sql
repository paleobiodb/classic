-- Convert schema '/data/MyApp/dbicdh/_source/deploy/5/001-auto.yml' to '/data/MyApp/dbicdh/_source/deploy/6/001-auto.yml':;

;
BEGIN;

;
ALTER TABLE authents ADD INDEX authents_idx_authorizer_no (authorizer_no),
                     ADD INDEX authents_idx_enterer_no (enterer_no),
                     ADD UNIQUE authents_enterer_no_authorizer_no (enterer_no, authorizer_no),
                     ADD CONSTRAINT authents_fk_authorizer_no FOREIGN KEY (authorizer_no) REFERENCES users (person_no) ON DELETE CASCADE ON UPDATE CASCADE,
                     ADD CONSTRAINT authents_fk_enterer_no FOREIGN KEY (enterer_no) REFERENCES users (person_no) ON DELETE CASCADE ON UPDATE CASCADE,
                     ENGINE=InnoDB DEFAULT CHARACTER SET utf8 COLLATE utf8_unicode_ci;

;

COMMIT;

