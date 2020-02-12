# 
# Paleobiology Database - classic backend image
# 
# The image 'paleobiodb_classic_preload' can be built using the file 'Dockerfile-preload'.
# See that file for more information.

FROM paleobiodb_classic_preload

COPY ./pbdb-classic/MyApp /data/MyApp
COPY ./pbdb-classic/Wing /data/Wing
COPY ./pbdb-new/lib/TableDefs.pm ./pbdb-new/lib/ExternalIdent.pm ./pbdb-new/lib/PBLogger.pm /data/MyApp/lib/

COPY app-common /var/paleobiodb/pbdb-apps/common
COPY app-resource-sub /var/paleobiodb/pbdb-apps/resource_sub
COPY app-archive /var/paleobiodb/pbdb-apps/archive
COPY app-test /var/paleobiodb/pbdb-apps/test

RUN ln -s /var/paleobiodb/pbdb-apps /data/MyApp/resources

ENV WING_CONFIG=/data/MyApp/etc/wing.conf

WORKDIR /data/MyApp/bin

CMD perl placeholder.pl

LABEL maintainer="mmcclenn@geology.wisc.edu"
LABEL version="1.0"
LABEL description="Paleobiology Database classic backend"

LABEL buildcheck="perl debug_web.psgi get /classic/ | head -20"


