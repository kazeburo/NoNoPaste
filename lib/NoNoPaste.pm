package NoNoPaste;

use Shirahata2;
use Scope::Container::DBI 0.03;
use Path::Class;
use Digest::SHA;
use NoNoPaste::Data;

our $VERSION = 0.01;

my $_on_connect = sub {
    my $connect = shift;
    $connect->do(<<EOF);
CREATE TABLE IF NOT EXISTS entries (
    id VARCHAR(255) NOT NULL PRIMARY KEY,
    nick VARCHAR(255) NOT NULL,
    body TEXT,
    ctime DATETIME NOT NULL
)
EOF
    $connect->do(<<EOF);
CREATE INDEX IF NOT EXISTS index_ctime ON entries ( ctime )
EOF
    return;
};

sub data {
    my $self = shift;
    my $db_path = Path::Class::file( $self->root_dir, "data", "nonopaste.db" );
    local $Scope::Container::DBI::DBI_CLASS = 'DBIx::Sunny'; 
    my $dbh = Scope::Container::DBI->connect( "dbi:SQLite:dbname=$db_path", '', '', {
        Callbacks => {
            connected => $_on_connect,
        },
    });
    NoNoPaste::Data->new( dbh => $dbh );
}

sub add_entry {
    my $self = shift;
    my (  $body, $nick ) = @_;
    $body = '' if ! defined $body;
    $nick = 'anonymouse' if ! defined $nick;
    my $id = substr Digest::SHA::sha1_hex($$ . join("\0", @_) . rand(1000) ), 0, 16;

    my $row = $self->data->add_entry(
        id => $id,
        nick => $nick,
        body => $body,
    );
    return ( $row ) ? $id : 0;
}

sub entry_list {
   my $self = shift;
   my $offset = shift || 0;
   my $rows = $self->data->entry_list( offset => $offset );
   
   my $next;
   $next = pop @$rows if @$rows > 10;

   return $rows, $next;
}

sub retrieve_entry {
   my $self = shift;
   my $id = shift;
   $self->data->retrieve_entry( id => $id );
}

get '/' => sub {
    my ( $self, $c )  = @_;

    my ($entries,$next) = $self->entry_list($c->req->param('offset'));
    $c->render('index',
               entries => $entries,
               next => $next );
};

post '/add' => sub {
    my ($self, $c) = @_;

    if ( $c->req->param('body') ) {
        my $id = $self->add_entry( $c->req->param('body'), $c->req->param('nick') );
        return $c->res->redirect( $c->req->uri_for('/entry/'.$id) ) if ( $id );
    }

    my ($entries,$next) = $self->entry_list;
    $c->render('index',
               entries => $entries,
               next => $next);
};

get '/entry/{id:[0-9a-f]{16}}' => sub {
    my ($self, $c) = @_;
    my $entry = $self->retrieve_entry($c->args->{id});
    return $c->res->not_found() unless $entry;

    $c->render('entry', entry => $entry );
};

get '/entry/{id:[0-9a-f]{16}}/raw' => sub {
    my ($self, $c) = @_;
    my $entry = $self->retrieve_entry($c->args->{id});
    return $c->res->not_found() unless $entry;
    $c->res->content_type('text/plain; charset=UTF-8');
    $c->res->body( $entry->{body} );
};

1;

__DATA__
@@ base
<html>
<head>
<title>NoNoPaste: Yet Another NoPaste</title>
<link rel="stylesheet" type="text/css" href="<: $c.req.uri_for('/static/js/prettify/prettify.css') :>" />
<link rel="stylesheet" type="text/css" href="<: $c.req.uri_for('/static/css/ui-lightness/jquery-ui-1.8.2.custom.css') :>" />
<link rel="stylesheet" type="text/css" href="<: $c.req.uri_for('/static/css/default.css') :>" />
</head>
<body>
<div id="container">
<div id="header">
<h1 class="title"><a href="<: $c.req.uri_for('/') :>">NoNoPaste: Yet Another NoPaste</a></h1>
<div class="welcome">
<ul>
<li><a href="<: $c.req.uri_for('/') :>">TOP</a></li>
</ul>
</div>
</div>

<div id="content">

: block content -> { }

</div>
</div>
<script src="<: $c.req.uri_for('/static/js/jquery-1.4.2.min.js') :>" type="text/javascript"></script>
<script src="<: $c.req.uri_for('/static/js/jstorage.js') :>" type="text/javascript"></script>
<script src="<: $c.req.uri_for('/static/js/prettify/prettify.js') :>" type="text/javascript"></script>
: block javascript -> {
<script type="text/javascript">
$(function() {
    prettyPrint();
});
</script>
: }
</body>
</html>


@@ index
: cascade 'base'

: around content -> {
<h2 class="subheader">新規投稿</h2>
: block form |  fillinform( $c.req ) -> {
<form method="post" action="/add" id="nopaste">
<textarea name="body" rows="20" cols="60"></textarea>
<label for="nick">nick</label>
<input type="text" id="nick" name="nick" value="" size="21" />
<input type="submit" id="post_nopaste" value="POST" />
</form>
: }  # block form

<h2 class="subheader">最新一覧</h2>
: for $entries -> $entry {
<div class="entry">
<pre class="prettyprint">
<: $entry.body :>
</pre>
<div class="entry_meta"><a href="<: $c.req.uri_for('/entry/' ~ $entry.id ~ '/raw') :>">raw</a> / <a href="<: $c.req.uri_for('/entry/' ~ $entry.id) :>" class="date"><: $entry.ctime :></a> / <span class="nick"><: $entry.nick :></span></div>
</div>
: }

<p class="paging">
: my $offset = $c.req.param('offset') || 0;
: if $offset >= 10 {
<a href="<: $c.req.uri_for('/', [ 'offset' => ($offset - 10) ] ) :>">Prev</a>
: }
: if $next {
<a href="<: $c.req.uri_for('/', [ 'offset' => ($offset + 10) ] ) :>">Next</a>
: }
</p>
: } #block content

: around javascript -> {
<script type="text/javascript">
$(function() {
    prettyPrint();
    $('#nopaste').submit( function(){
        $.jStorage.set( "nick", $('#nick').val() );
        return true;
    });
    if ( $('#nick').val().length == 0 ) {
        $('#nick').val( $.jStorage.get("nick") );
    }
});
</script>
: } #block javascript

@@ entry
: cascade 'base'

: around content -> {
<h2 class="subheader"><a href="<: $c.req.uri_for('/entry/' ~ $entry.id) :>"><: $c.req.uri_for('/entry/' ~ $entry.id) :></a></h2>
<div class="entry">
<pre class="prettyprint">
<: $entry.body :>
</pre>
<div class="entry_meta"><a href="<: $c.req.uri_for('/entry/' ~ $entry.id ~ '/raw') :>">raw</a> / <a href="<: $c.req.uri_for('/entry/' ~ $entry.id) :>" class="date"><: $entry.ctime :></a> / <span class="nick"><: $entry.nick :></span></div>
</div>
: } # content




