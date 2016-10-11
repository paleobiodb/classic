-- Convert schema '/data/MyApp/dbicdh/_source/deploy/4/001-auto.yml' to '/data/MyApp/dbicdh/_source/deploy/3/001-auto.yml':;

;
BEGIN;

;
DROP TABLE pbdb.session_data;

;
ALTER TABLE authorizer_enterers DROP FOREIGN KEY authorizer_enterers_fk_authorizer_id,
                                DROP FOREIGN KEY authorizer_enterers_fk_enterer_id;

;
DROP TABLE authorizer_enterers;

;

COMMIT;

