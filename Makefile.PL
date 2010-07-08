use inc::Module::Install;
name 'NoNoPaste';
all_from 'lib/NoNoPaste.pm';

tests 't/*.t';
#author_tests 'xt';

test_requires 'Test::More';

requires 'local::lib';
requires 'Class::Accessor::Fast';
requires 'Data::Section::Simple';
requires 'Path::Class';
requires 'Scalar::Util';
requires 'Plack', 0.9937;
requires 'Net::IP';
requires 'Plack::Middleware::Access';
requires 'Plack::Middleware::ReverseProxy';
requires 'Router::Simple';
requires 'Text::MicroTempate::DataSection';
requires 'Text::MicroTempate::Extended', 0.11;
requires 'HTML::FillInForm::Lite', 1.09;
requires 'Cwd';
requires 'File::Basename';

requires 'DBI';
requires 'DBD::SQLite', 1.25;
requires 'Digest::MD5';

#auto_set_repository;
auto_include;
WriteAll;
