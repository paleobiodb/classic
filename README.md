# Paleobiology Database Web Application (Version 2.0)

This repository contains the active source code for the PBDB web interface and application. This version encapsulates
much of the earlier CGI based code in a proper web application framework. A new templating engine, user management system
and many other more robust services are provided by this new configuration. The "classic" codebase (retroactively referred to
as version 1) exists in a separate repository but development has ceased and it has been removed from production deployment.
It is hoped that this cleaner and more modern version of the database frontend will lead to more active and rapid development
in the future.

## Issue reporting
Please raise issues related to the database in general on the PBDB Change Log repository. Issues on this repository should be
reserved for the core development team. This application is deployed live at [http://paleobiodb.org](http://paleobiodb.org)
and specific bugs related to its operation should be reported to [admin@paleobiodb.org](mailto:admin@paleobiodb.org).

## Core developers
* [Michael McClennen](http://github.com/mmcclenn) "mmcclenn"
* [Julian Jenkins](http://github.com/jpjenk) "jpjenk"

## Dependencies
* The PBDB application is written in Perl5 and, like any large project, relies on a number of public modules for text
handling, database access, map generation, http access, error reporting and other services. All auxiliary modules are commonly
utilized stable code. They are in the public domain and available from the [CPAN](https://metacpan.org) archive.
* The [Starman](https://github.com/miyagawa/Starman) PSGI app server and [Dancer](http://perldancer.org) web app framework.
* The [Wing](https://github.com/plainblack/Wing) web services toolkit which provides middleware and a REST API server in
addition to a template engine, job que, Angular.js applets and many professional tools for website operation and management.
* [Web::DataService](https://metacpan.org/pod/Web::DataService) a data service framework written by
[mmcclenn](http://github.com/mmcclenn) which fulfills http-based data requests. This framework also provides the public
RESTful API for the PBDB outside of the context of the web application.

## Database Description
The Paleobiology Database (PBDB) is a non-governmental, non-profit public resource for paleontological data.
It has been organized and operated by a multi-disciplinary, multi-institutional, international group of paleobiological
researchers. Its purpose is to provide global, collection-based occurrence and taxonomic data for organisms of all
geological ages, as well data services to allow easy access to data for independent development of analytical tools,
visualization software, and applications of all types. The Database’s broader goal is to encourage and enable data-driven
collaborative efforts that address large-scale paleobiological questions.

More information about the PBDB can be found [here](https://paleobiodb.org/#/faq).
