package Shirahata;

use strict;
use warnings;
use Carp qw//;
use Scalar::Util qw/blessed/;
use base qw/Class::Accessor::Fast/;
use Plack::Builder;
use Router::Simple;
use Data::Section::Simple;
use Text::Xslate qw(mark_raw);
use HTML::FillInForm::Lite qw(fillinform);
use Path::Class;
use Net::IP;

__PACKAGE__->mk_accessors(qw/root_dir/);
our @EXPORT = qw/get post any/;

sub import {
    my ($class, $name) = @_;
    my $caller = caller;
    {
        no strict 'refs';
        if ( $name && $name =~ /^-base/ ) {
            if ( ! $caller->isa($class) && $caller ne 'main' ) {
                push @{"$caller\::ISA"}, $class;
                for my $func (@EXPORT) {
                    *{"$caller\::$func"} = \&$func;
                }
            }

        }
    }
    strict->import;
    warnings->import;
}

sub new {
    my $class = shift;
    my $root_dir = shift;
    $class->SUPER::new({ root_dir => $root_dir });
}

sub psgi {
    my $self = shift;

    my @allowfrom = map { s/\s//g } split(/,/, $ENV{ACCESS_ALLOW_FROM} || "");
    my @frontproxy = map { s/\s//g } split(/,/, $ENV{FRONT_PROXY} || "");

    my @frontproxies;
    foreach my $ip ( @frontproxy ) {
        my $netip = Net::IP->new($ip)
            or die "not supported type of rule argument [$ip] or bad ip: " . Net::IP::Error();
        push @frontproxies, $netip;
    }

    my $app = $self->build_app;
    $app = builder {
        if ( @frontproxies ) {
            enable_if {
                my $addr = $_[0]->{REMOTE_ADDR};
                my $netip;
                if ( defined $addr && ($netip = Net::IP->new($addr)) ) {
                    for my $proxy ( @frontproxies ) {
                       my $overlaps = $proxy->overlaps($netip);
                       if ( $overlaps == $IP_B_IN_A_OVERLAP || $overlaps == $IP_IDENTICAL ) {
                           return 1;
                       } 
                    }
                }
                return;
            } "Plack::Middleware::ReverseProxy";
        }
        if ( @allowfrom ) {
            my @rule;
            for ( @allowfrom ) {
                push @rule, 'allow', $_;
            }
            push @rule, 'deny', 'all';
            enable 'Plack::Middleware::Access', rules => \@rule;
        }
        enable 'Plack::Middleware::Static',
            path => qr{^/(favicon\.ico$|static/)},
            root =>Path::Class::dir($self->{root_dir}, 'htdocs')->stringify;
        $app;
    };
}

sub build_template {
    my $self = shift;
    if ( !$self->{_templates_dir} ) {
         my $reader = Data::Section::Simple->new(ref $self);
         my $all = $reader->get_data_section;

         $self->{_template_dir} = File::Temp::tempdir( CLEANUP => 1 ); 
         for my $section ( keys %$all ) {
             my $fh = Path::Class::file( $self->{_template_dir}, $section )->openw;
             print $fh $all->{$section};
         }
    }
    $self->{_template_dir};
}

sub build_app {
    my $self = shift;

    my $tx = Text::Xslate->new(
        path => [ $self->build_template ],
        cache_dir => File::Temp::tempdir( CLEANUP => 1 ),
        input_layer => ':raw',
        function => {
            fillinform => sub {
                my $q = shift;
                return sub { 
                    my $fif = HTML::FillInForm::Lite->new(layer => ':raw');
                    my $output = $fif->fill(\$_[0], $q);
                    mark_raw( $output )
                };
            },
        },
    );

    sub {
        my $env = shift;
        my $psgi_res;

        my $s_req = Shirahata::Request->new($env);
        my $s_res = Shirahata::Response->new(200);
        $s_res->content_type('text/html; charset=UTF-8');

        my $c = Shirahata::Connection->new({
            _tx => $tx,
            req => $s_req,
            res => $s_res,
            stash => {},
        });

        if ( my $p = $self->router->match($env) ) {
            my $code = delete $p->{action};
            return $self->ise('uri match but no action found') unless $code;

            $c->args($p);

            my $res = $code->($self, $c );
            Carp::croak( "undefined response") if ! defined $res;

            my $res_t = ref($res) || '';
            if ( blessed $res && $res->isa('Plack::Response') ) {
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
            $psgi_res = $c->res->not_found->finalize;
        }

        $psgi_res;
    };
}

my $_ROUTER;
sub router {
    my $class = shift;
    if ( !$_ROUTER ) {
        $_ROUTER = Router::Simple->new();
    }
    $_ROUTER;
}

sub _any($$$;$) {
    my $class = shift;
    if ( @_ == 3 ) {
        my ( $methods, $pattern, $code ) = @_;
        $class->router->connect(
            $pattern,
            { action => $code },
            { method => [ map { uc $_ } @$methods ] } 
        );        
    }
    else {
        my ( $pattern, $code ) = @_;
        $class->router->connect(
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

package Shirahata::Connection;

use strict;
use warnings;
use base qw/Class::Accessor::Fast/;

__PACKAGE__->mk_accessors(qw/req res stash args _tx/);

*request = \&req;
*response = \&res;

sub render {
    my $self = shift;
    my $file = shift;
    my %args = ( @_ && ref $_[0] ) ? %{$_[0]} : @_;
    my %vars = (
        args => $self->args,
        req => $self->req,
        res => $self->res,
        stash => $self->stash,
        %args,
    );
    my $body = $self->_tx->render($file, \%vars);
    $self->res->status( 200 );
    $self->res->content_type('text/html; charset=UTF-8');
    $self->res->body( $body );
    $self->res;
}

1;

package Shirahata::Request;

use strict;
use warnings;
use base qw/Plack::Request/;

sub uri_for {
     my($self, $path, $args) = @_;
     my $uri = $self->base;
     $uri->path($path);
     $uri->query_form(@$args) if $args;
     $uri;
}

1;

package Shirahata::Response;

use strict;
use warnings;
use base qw/Plack::Response/;

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


