package NoNoPaste::Web;

use strict;
use warnings;
use Carp qw//;
use Encode qw//;
use Scalar::Util qw/refaddr/;
use base qw/Class::Data::Inheritable Class::Accessor::Fast/;
use Plack::Loader;
use Plack::Builder;
use Plack::Request;
use Plack::Response;
use Router::Simple;
use Text::MicroTemplate;
use Data::Section::Simple;
use NoNoPaste::Web::Request;
use Path::Class;
use Net::IP;

__PACKAGE__->mk_classdata('_ROUTER');
__PACKAGE__->mk_accessors(qw/root_dir
                             allowfrom
                             frontproxy/);

our @EXPORT = qw/get post any/;

sub import {
    my ($class, $name) = @_;
    my $caller = caller;
    {
        no strict 'refs';
        if ( $name && $name =~ /^-base/ ) {
            if ( ! $caller->isa($class) && $caller ne 'main' ) {
                push @{"$caller\::ISA"}, $class;
            }
        }
        for my $func (@EXPORT) {
            *{"$caller\::$func"} = \&$func;
        }
    }

    strict->import;
    warnings->import;
}

sub new {
    my $class = shift;
    my $root_dir = shift;

    my @allowfrom = map { s/\s//g } split(/,/, $ENV{ACCESS_ALLOW_FROM} || "");
    my @frontproxy = map { s/\s//g } split(/,/, $ENV{FRONT_PROXY} || "");
    $class->SUPER::new({
        root_dir => $root_dir,
        allowfrom => \@allowfrom,
        frontproxy => \@frontproxy,
    });
}

sub psgi {
    my $self = shift;

    my $allowfrom = $self->allowfrom || [];
    my $frontproxy = $self->frontproxy || [];
    my @frontproxies;
    foreach my $ip ( @$frontproxy ) {
        my $netip = Net::IP->new($ip)
            or die "not supported type of rule argument [$ip] or bad ip: " . Net::IP::Error();
        push @frontproxies, $netip;
    }

    my $app = $self->build_app;
    $app = builder {
        enable 'Plack::Middleware::Lint';
        enable 'Plack::Middleware::StackTrace';
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
        if ( @$allowfrom ) {
            my @rule;
            for ( @$allowfrom ) {
                push @rule, 'allow', $_;
            }
            push @rule, 'deny', 'all';
            enable 'Plack::Middleware::Access', rules => \@rule;
        }
        enable 'Plack::Middleware::Static',
            path => qr{^/(favicon\.ico$|static/)}, root => Path::Class::dir($self->root_dir, 'htdocs')->stringify;
        $app;
    };
}


sub build_app {
    my $self = shift;
    sub {
        my $env = shift;
        if ( my $p = $self->router->match($env) ) {
            my $code = delete $p->{action};
            return $self->ise('uri match but no action found') unless $code;

            my $req = NoNoPaste::Web::Request->new($env);
            my $res = $code->($self, $req, $p);

            my $res_t = ref $res || '';
            if ( $res_t eq 'Plack::Response' ) {
                return $res->finalize;
            }
            elsif ( $res_t eq 'ARRAY' ) {
                return $res;
            }
            elsif ( !$res_t ) {
                return $self->html_response( $res );
            }
            else {
                Carp::croak("unknown response type: $res, $res_t");
            }
        }
        return $self->not_found();
    };
}

sub ise {
    my $self = shift;
    my $error = shift;
    $error ||= 'Internal Server Error';
    return [ 500, [ 'Content-Type' => 'text/html; charset=utf-8' ], [$error] ];
}

sub not_found {
    my $self = shift;
    my $error = shift;
    $error ||= 'Not Found';
    return [ 404, [ 'Content-Type' => 'text/html; charset=utf-8' ], [$error] ];
}

sub redirect {
    my $self = shift;
    my $uri = shift;
    return [ 302, [ 'Location' => $uri ], ['redirect'] ];
    
}

sub html_response {
    my $self = shift;
    my $message = shift;
    return [ 200, [ 'Content-Type' => 'text/html; charset=utf-8'], [ $message ] ];
}

sub render {
    my ( $self, $key, @args ) = @_;
    my $code = do {
        my $reader = Data::Section::Simple->new(ref $self);
        my $tmpl = $reader->get_data_section($key);
        Carp::croak("unknown template file:$key") unless $tmpl;
        Text::MicroTemplate->new(template => $tmpl, package_name => ref($self) )->code();
    };

    package DB;
    local *DB::render = sub {
        my $coderef = (eval $code); ## no critic
        die "Cannot compile template '$key': $@" if $@;
        my $html = $coderef->(@args);
        $html = Encode::encode_utf8($html) if utf8::is_utf8($html);
        $html;
    };
    goto &DB::render;
}

sub router {
    my $class = shift;
    my $router = $class->_ROUTER;
    if ( !$router ) {
        $router = $class->_ROUTER( Router::Simple->new() );
    }
    $router;
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


