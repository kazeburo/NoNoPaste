use inc::Module::Install;
name 'NoNoPaste';
all_from 'lib/NoNoPaste.pm';

tests 't/*.t';
#author_tests 'xt';

test_requires 'Test::More';

requires 'local::lib';
requires 'Class::Data::Inheritable';
requires 'Class::Accessor::Fast';
requires 'Data::Section::Simple';
requires 'UNIVERSAL::require';
requires 'Path::Class';
requires 'URI::Escape';
requires 'Scalar::Util';
requires 'Plack', 0.9937;
requires 'Net::IP';
requires 'Plack::Middleware::Access';
requires 'Plack::Middleware::ReverseProxy';
requires 'Router::Simple';
requires 'Text::MicroTemplate';
requires 'Gearman::Client', 1.10;
requires 'Gearman::Server';
requires 'Digest::MD5';

requires 'DBI';
requires 'DBD::SQLite', 1.25;

#auto_set_repository;
auto_include;
WriteAll;
