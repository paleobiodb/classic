# 
# Paleobiology Database - Classic Web Application

FROM perl:5.26-threaded AS paleobiodb_classic_preload

RUN apt-get update && \
    apt-get -y install apt-utils && \
    apt-get -y install mariadb-client && \
    apt-get -y install beanstalkd && \
    cpanm DBI && \
    cpanm DBD::mysql && \
    cpanm Dancer && \
    cpanm Moo && \
    cpanm Moose && \
    cpanm DBIx::Class && \
    cpanm CHI && \
    cpanm IO::File && \
    cpanm YAML && \
    cpanm Email::Sender::Simple && \
    cpanm Email::MIME::Kit && \
    cpanm Email::Sender && \
    cpanm Config::JSON && \
    cpanm Ouch && \
    cpanm Log::Log4perl && \
    cpanm Plugin::Tiny && \
    cpanm Beanstalk::Client && \
    cpanm DateTime && \
    cpanm DateTime::Format::MySQL && \
    cpanm DBIx::Class::UUIDColumns && \
    cpanm DBIx::Class::TimeStamp && \
    cpanm DBIx::Class::InflateColumn::Serializer && \
    cpanm Data::GUID && \
    cpanm Crypt::Eksblowfish::Bcrypt && \
    cpanm String::Random && \
    cpanm Cache::FastMmap && \
    cpanm Data::Serializer && \
    cpanm Text::CSV_XS && \
    cpanm Class::Date && \
    cpanm Mail::Mailer && \
    cpanm Wing::Client && \
    cpanm JSON::XS && \
    cpanm Server::Starter && \
    cpanm Starman && \
    cpanm Plack::Middleware::MethodOverride && \
    cpanm Plack::Middleware::SizeLimit && \
    cpanm Plack::Middleware::CrossOrigin && \
    cpanm Net::Server::SS::PreFork && \
    cpanm Template::Toolkit && \
    cpanm Dancer::Logger::Log4perl

RUN apt-get install -y vim

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


