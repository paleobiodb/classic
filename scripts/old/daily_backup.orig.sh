#!/bin/bash
source config/backup.conf
OF=pbdb-backup-$(date +%Y%m%d)
OFW=pbdb-wing-backup-$(date +%Y%m%d)
LATEST=pbdb-latest
LATESTW=pbdb-wing-latest

echo "Backing up the Paleobiology Database to $MYSQL_BACKUP_DIR/$OF.gz and $MYSQL_BACKUP_DIR/$OFW.gz";

# mysqldump method (preferred)
/opt/local/lib/mariadb/bin/mysqldump -u pbdb_backup -p$MYSQL_BACKUP_PASSWD --opt pbdb | gzip > "$MYSQL_BACKUP_DIR/$OF.gz"
/opt/local/lib/mariadb/bin/mysqldump -u pbdb_backup -p$MYSQL_BACKUP_PASSWD --opt pbdb_wing | gzip > "$MYSQL_BACKUP_DIR/$OFW.gz"
#| gzip > "$MYSQL_BACKUP_DIR/$OF.gz"
cd "$MYSQL_BACKUP_DIR"
ln -sF $OF.gz $LATEST.gz
scp $LATEST.gz guest@paleodb.science.mq.edu.au:pbdb_latest.gz
scp -P 2200 $LATEST.gz pbdbimport@erlangen.paleobiodb.org:/home/pbdbimport/dbimport
ln -sF $OFW.gz $LATESTW.gz
