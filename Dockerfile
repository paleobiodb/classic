# 
# Paleobiology Database - classic backend image
# 
# The image 'paleobiodb_classic_preload' can be built using the file 'Dockerfile-preload'.
# See that file for more information.

FROM paleobiodb_classic_preload

COPY pbdb-classic/MyApp /data/MyApp
COPY pbdb-classic/Wing /data/Wing
COPY pbdb-new/lib /data/MyApp/lib/PBData
COPY pbdb-app/ /data/MyApp/resources

ENV WING_CONFIG=/data/MyApp/etc/wing.conf

WORKDIR /data/MyApp

CMD perl placeholder.pl

LABEL maintainer="mmcclenn@geology.wisc.edu"
LABEL version="1.0"
LABEL description="Paleobiology Database classic backend"

LABEL buildcheck="perl bin/debug_web.psgi get /classic/ | head -20"


