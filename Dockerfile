# 
# Paleobiology Database - Classic backend image
# 
# The image 'paleomacro_classic_preload' is built from the file 'Dockerfile-preload'
# in this directory. You can pull the latest version of that image from the remote
# container repository associated with this project using the command 'pbdb pull classic'.
# Alternatively, you can build locally it using the command 'pbdb build classic preload'.
# See the file Dockerfile-preload for more information.
# 
# Once you have the preload image, you can build the Classic container image using
# the command 'pbdb build classic'.

FROM paleomacro_classic_preload

EXPOSE 6000 6001 6003

WORKDIR /data/MyApp

# To build this container with the proper timezone setting, use --build-arg TZ=xxx
# where xxx is the timezone in which the server is located. The 'pbdb build' command
# will do this automatically. Without any argument it will default to UTC, with no
# local time available. To override the language setting, use --build-arg LANG=xxx.

ARG TZ=Etc/UTC

RUN echo $TZ > /etc/timezone && \
    ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && \
    dpkg-reconfigure -f noninteractive tzdata

ENV LANG=en_US.UTF-8

ENV TZ=$TZ

ENV WING_CONFIG=/data/MyApp/etc/wing.conf
ENV WING_HOME=/data/Wing
ENV WING_APP=/data/MyApp

CMD ["perl", "bin/start_classic.pl"]

COPY classic/patch/error-render.patch /var/tmp/error-render.patch
RUN patch `perl -MDancer::Error -e 'print $INC{"Dancer/Error.pm"}'` /var/tmp/error-render.patch

COPY classic /data/MyApp
COPY wing /data/Wing
COPY wing/bin/wing /usr/local/bin/
COPY pbapi/lib /data/MyApp/lib/PBData
COPY pbdb-app/ /data/MyApp/resources

RUN mkdir -p /data/MyApp/captcha/temp

LABEL maintainer="mmcclenn@geology.wisc.edu"
LABEL version="1.0"
LABEL description="Paleobiology Database classic backend"

LABEL buildcheck="perl bin/debug_web.psgi get /classic/ | head -20"


