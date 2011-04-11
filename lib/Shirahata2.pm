package Shirahata2;

use strict;
use warnings;
use utf8;
use Carp qw//;
use Scalar::Util qw//;
use Plack::Builder;
use Plack::Builder::Conditionals -prefix => 'c';
use Router::Simple;
use Cwd qw//;
use File::Basename qw//;
use Path::Class;

use Text::Xslate 1.1003;
use Data::Section::Simple;
use HTML::FillInForm::Lite qw//;

use Class::Accessor::Lite (
    new => 0,
    rw => [qw/root_dir/]
);

our @EXPORT = qw/new root_dir psgi build_app _router _any get post any/;

sub import {
    my ($class, $name) = @_;
    my $caller = caller;
    for my $func (@EXPORT) {
        no strict 'refs';
        *{"$caller\::$func"} = \&$func;
    }
    strict->import;
    warnings->import;
    utf8->import;
}

sub new {
    my $class = shift;
    my $root_dir = shift;
    my @caller = caller;
    $root_dir ||= File::Basename::dirname( Cwd::realpath($caller[1]) );
    bless { root_dir => $root_dir }, $class;
}

sub psgi {
    my $self = shift;
    if ( ! ref $self ) {
        my $root_dir = shift;
        my @caller = caller;
        $root_dir ||= File::Basename::dirname( Cwd::realpath($caller[1]) );
        $self = $self->new($root_dir);
    }

    my @allowfrom = map { s/\s//g } split(/,/, $ENV{ACCESS_ALLOW_FROM} || "");
    my @frontproxy = map { s/\s//g } split(/,/, $ENV{FRONT_PROXY} || "");

    my $app = $self->build_app;
    $app = builder {
        if ( @frontproxy ) {
            enable c_match_if c_addr(@frontproxy), 'ReverseProxy';
        }
        if ( @allowfrom ) {
            my @rule;
            for ( @allowfrom ) {
                push @rule, 'allow', $_;
            }
            push @rule, 'deny', 'all';
            enable 'Access', rules => \@rule;
        }
        enable 'Static',
            path => qr{^/(favicon\.ico$|static/)},
            root =>Path::Class::dir($self->{root_dir}, 'htdocs')->stringify;
        enable 'Scope::Container';
        $app;
    };
}

sub build_app {
    my $self = shift;

    #router
    my $router = Router::Simple->new;
    $router->connect(@{$_}) for @{$self->_router};

    #template
    my $reader = Data::Section::Simple->new(ref $self);
    my $templates = $reader->get_data_section;
    
    #xslate
    my $fif = HTML::FillInForm::Lite->new();
    my $tx = Text::Xslate->new(
        path => [ $templates ],
        function => {
            fillinform => sub {
                my $q = shift;
                return sub {
                    my ($html) = @_;
                    return Text::Xslate::mark_raw( $fif->fill( \$html, $q ) );
                }
            }
        },
    );

    sub {
        my $env = shift;
        my $psgi_res;

        my $s_req = Shirahata2::Request->new($env);
        my $s_res = Shirahata2::Response->new(200);
        $s_res->content_type('text/html; charset=UTF-8');

        my $c = Shirahata2::Connection->new({
            tx => $tx,
            req => $s_req,
            res => $s_res,
            stash => {},
        });

        if ( my $p = $router->match($env) ) {
            my $code = delete $p->{action};
            return $self->ise('uri match but no action found') unless $code;

            $c->args($p);

            my $res = $code->($self, $c );
            Carp::croak( "undefined response") if ! defined $res;

            my $res_t = ref($res) || '';
            if ( Scalar::Util::blessed $res && $res->isa('Plack::Response') ) {
                $psgi_res = $res->finalize;
            }
            elsif ( $res_t eq 'ARRAY' ) {
                $psgi_res = $res;
            }
            elsif ( !$res_t ) {
                $s_res->body($res);
                $psgi_res = $s_res->finalize;
            }
            else {
                Carp::croak("unknown response type: $res, $res_t");
            }
        }
        else {
            # router not match
            $psgi_res = $c->res->not_found()->finalize;
        }
        
        $psgi_res;
    };
}

my $_ROUTER={};
sub _router {
    my $klass = shift;
    my $class = ref $klass ? ref $klass : $klass; 
    if ( !$_ROUTER->{$class} ) {
        $_ROUTER->{$class} = [];
    }    
    if ( @_ ) {
        push @{ $_ROUTER->{$class} }, [@_];
    }
    $_ROUTER->{$class};
}

sub _any($$$;$) {
    my $class = shift;
    if ( @_ == 3 ) {
        my ( $methods, $pattern, $code ) = @_;
        $class->_router(
            $pattern,
            { action => $code },
            { method => [ map { uc $_ } @$methods ] } 
        );        
    }
    else {
        my ( $pattern, $code ) = @_;
        $class->_router(
            $pattern,
            { action => $code }
        );
    }
}

sub any {
    my $class = caller;
    $class->_any( @_ );
}

sub get {
    my $class = caller;
    $class->_any( ['GET','HEAD'], $_[0], $_[1]  );
}

sub post {
    my $class = caller;
    $class->_any( ['POST'], $_[0], $_[1]  );
}

1;

package Shirahata2::Connection;

use strict;
use warnings;
use Class::Accessor::Lite (
    new => 1,
    rw => [qw/req res stash args tx/]
);

*request = \&req;
*response = \&res;

sub render {
    my $self = shift;
    my $file = shift;
    my %args = ( @_ && ref $_[0] ) ? %{$_[0]} : @_;
    my %vars = (
        c => $self,
        stash => $self->stash,
        %args,
    );

    my $body = $self->tx->render($file, \%vars);
    $self->res->status( 200 );
    $self->res->content_type('text/html; charset=UTF-8');
    $self->res->body( $body );
    $self->res;
}

1;

package Shirahata2::Request;

use strict;
use warnings;
use parent qw/Plack::Request/;
use Hash::MultiValue;
use Encode;

sub body_parameters {
    my ($self) = @_;
    $self->{'shirahata2.body_parameters'} ||= $self->_decode_parameters($self->SUPER::body_parameters());
}

sub query_parameters {
    my ($self) = @_;
    $self->{'shirahata2.query_parameters'} ||= $self->_decode_parameters($self->SUPER::query_parameters());
}

sub _decode_parameters {
    my ($self, $stuff) = @_;

    my @flatten = $stuff->flatten();
    my @decoded;
    while ( my ($k, $v) = splice @flatten, 0, 2 ) {
        push @decoded, Encode::decode_utf8($k), Encode::decode_utf8($v);
    }
    return Hash::MultiValue->new(@decoded);
}
sub parameters {
    my $self = shift;

    $self->env->{'shirahata2.request.merged'} ||= do {
        my $query = $self->query_parameters;
        my $body  = $self->body_parameters;
        Hash::MultiValue->new( $query->flatten, $body->flatten );
    };
}

sub body_parameters_raw {
    shift->SUPER::body_parameters();
}
sub query_parameters_raw {
    shift->SUPER::query_parameters();
}

sub parameters_raw {
    my $self = shift;

    $self->env->{'plack.request.merged'} ||= do {
        my $query = $self->SUPER::query_parameters();
        my $body  = $self->SUPER::body_parameters();
        Hash::MultiValue->new( $query->flatten, $body->flatten );
    };
}

sub param_raw {
    my $self = shift;

    return keys %{ $self->parameters_raw } if @_ == 0;

    my $key = shift;
    return $self->parameters_raw->{$key} unless wantarray;
    return $self->parameters_raw->get_all($key);
}

sub uri_for {
     my($self, $path, $args) = @_;
     my $uri = $self->base;
     $uri->path($path);
     $uri->query_form(@$args) if $args;
     $uri;
}

1;

package Shirahata2::Response;

use strict;
use warnings;
use parent qw/Plack::Response/;
use Encode;

sub _body {
    my $self = shift;
    my $body = $self->body;
       $body = [] unless defined $body;
    if (!ref $body or Scalar::Util::blessed($body) && overload::Method($body, q("")) && !$body->can('getline')) {
        return [ Encode::encode_utf8($body) ];
    } else {
        return $body;
    }
}

sub redirect {
    my $self = shift;
    if ( @_ ) {
        $self->SUPER::redirect(@_);
        return $self;
    }
    $self->SUPER::redirect();
}

sub server_error {
    my $self = shift;
    my $error = shift;
    $self->status( 500 );
    $self->content_type('text/html; charset=UTF-8');
    $self->body( $error || 'Internal Server Error' );
    $self;
}

sub not_found {
    my $self = shift;
    my $error = shift;
    $self->status( 500 );
    $self->content_type('text/html; charset=UTF-8');
    $self->body( $error || 'Not Found' );
    $self;
}



1;


