#!/usr/bin/perl

use strict;
use warnings;
use Cwd qw/realpath/;
use File::Basename qw/dirname/;
use NoNoPaste::Web::Root;

my $root_dir = dirname( realpath(__FILE__) );
my $web = NoNoPaste::Web::Root->new($root_dir);
$web->psgi;

