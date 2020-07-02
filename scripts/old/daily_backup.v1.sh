#!/bin/bash
source config/backup.conf
OF=pbdb-backup-$(date +%Y%m%d)
OFW=pbdb-wing-backup-$(date +%Y%m%d)
LATEST=pbdb-latest
LATESTW=pbdb-wing-latest
CORE_DUMP=pbdb-core
CORE_TABLES="authorities collections ecotaph intervals interval_lookup measurements occurrences opinions permissions person pubs refs reidentifications secondary_refs specimens taxa_tree_cache"

# first dump the databases

echo "Backing up the Paleobiology Database to $MYSQL_BACKUP_DIR/$OF.gz"
/opt/local/lib/mariadb/bin/mysqldump -u pbdb_backup -p$MYSQL_BACKUP_PASSWD --opt pbdb | gzip > "$MYSQL_BACKUP_DIR/$OF.gz"

echo "Backing up core tables to $MYSQL_BACKUP_DIR/$CORE_DUMP.gz"
/opt/local/lib/mariadb/bin/mysqldump -u pbdb_backup -p$MYSQL_BACKUP_PASSWD --opt pbdb $CORE_TABLES | gzip > "$MYSQL_BACKUP_DIR/$CORE_DUMP.gz"

echo "Backing up wing tables to $MYSQL_BACKUP_DIR/$OFW.gz"
/opt/local/lib/mariadb/bin/mysqldump -u pbdb_backup -p$MYSQL_BACKUP_PASSWD --opt pbdb_wing | gzip > "$MYSQL_BACKUP_DIR/$OFW.gz"

# set the symlink 'pbdb-latest.gz' to point to the latest full backup

cd "$MYSQL_BACKUP_DIR"
ln -sF $OF.gz $LATEST.gz
ln -sF $OFW.gz $LATESTW.gz

# now copy the zipped dump files to remote sites

echo "Copying core files to Macquarie"

scp $CORE_DUMP.gz guest@paleodb.science.mq.edu.au:pbdb_core.gz

echo "Copying full dump to Erlangen"

scp -P 2200 $LATEST.gz pbdbimport@erlangen.paleobiodb.org:/home/pbdbimport/dbimport

echo "Done."
echo ""
