# 
# Paleobiology Database - classic backend image
# 
# The image 'paleobiodb_classic_preload' can be built using the file 'Dockerfile-preload'.
# See that file for more information.

FROM paleomacro_classic_preload

COPY pbdb-classic /data/MyApp
COPY pbdb-wing /data/Wing
COPY pbdb-wing/bin/wing /usr/local/bin/
COPY pbdb-new/lib /data/MyApp/lib/PBData
COPY pbdb-app/ /data/MyApp/resources

ENV WING_CONFIG=/data/MyApp/etc/wing.conf
ENV WING_HOME=/data/Wing
ENV WING_APP=/data/MyApp

WORKDIR /data/MyApp

CMD perl placeholder.pl

LABEL maintainer="mmcclenn@geology.wisc.edu"
LABEL version="1.0"
LABEL description="Paleobiology Database classic backend"

LABEL buildcheck="perl bin/debug_web.psgi get /classic/ | head -20"


