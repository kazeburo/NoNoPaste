package NoNoPaste::Web::Root;

use strict;
use warnings;
use NoNoPaste::Web -base;
use DBI qw(:sql_types); 
use Path::Class;
use Digest::MD5;

sub dbh {
    my $self = shift;
    return $self->{__dbh} if $self->{__dbh};

    my $db_path = Path::Class::file( $self->root_dir, "data", "nonopaste.db" );
    my $dbh = DBI->connect( "dbi:SQLite:dbname=$db_path","","",
                            { RaiseError => 1, AutoCommit => 1 } );
    $dbh->do(<<EOF);
CREATE TABLE IF NOT EXISTS entries (
    id VARCHAR(255) NOT NULL PRIMARY KEY,
    nick VARCHAR(255) NOT NULL,
    body TEXT,
    ctime DATETIME NOT NULL
)
EOF

    $dbh->do(<<EOF);
CREATE INDEX IF NOT EXISTS index_ctime ON entries ( ctime )
EOF
    
    $dbh;
}

sub add_entry {
    my $self = shift;
    my (  $body, $nick ) = @_;
    $body = '' if ! defined $body;
    $nick = 'anonymouse' if ! defined $nick;

    my $id = substr Digest::MD5::md5_hex($$ . $self . join("\0", @_) . rand(1000) ), 0, 16;

   my $sth = $self->dbh->prepare(<<EOF);
INSERT INTO entries ( id, nick, body, ctime ) values ( ?, ?, ?, DATETIME('now') )
EOF
    my $row = $sth->execute( $id, $nick, $body );
    return ( $row == 1 ) ? $id : 0;
}

sub entry_list {
   my $self = shift;
   my $offset = shift || 0;

   my $sth = $self->dbh->prepare(<<EOF);
SELECT id,nick,body,ctime FROM entries ORDER BY ctime DESC LIMIT ?,11
EOF
   $sth->bind_param(1, $offset,  SQL_INTEGER);
   $sth->execute();

   my @ret;
   while ( my $row = $sth->fetchrow_hashref ) {
       push @ret, $row;
       last if @ret == 10;
   }
  
   my $next = $sth->fetchrow_hashref;
   return \@ret, $next;
}

sub retrieve_entry {
   my $self = shift;
   my $id = shift;

   my $sth = $self->dbh->prepare(<<EOF);
SELECT id,nick,body,ctime FROM entries WHERE id = ?
EOF
   $sth->execute($id);

   return $sth->fetchrow_hashref;
}


get '/' => sub {
    my ( $self, $req, $p )  = @_;
    my ($entries,$next) = $self->entry_list($req->param('offset'));
    return $self->render('index.mt');
};

post '/add' => sub {
    my ($self, $req, $p) = @_;

    if ( $req->param('body') ) {
        my $id = $self->add_entry( $req->param('body'), $req->param('nick') );
        return $self->redirect( $req->uri_for('/entry/'.$id) ) if ( $id );
    }

    my ($entries,$next) = $self->entry_list;
    $self->render('index.mt');
};

get '/entry/{id:[0-9a-f]{16}}' => sub {
    my ($self, $req, $p) = @_;
    my $entry = $self->retrieve_entry($p->{id});
    return $self->not_found() unless $entry;

    $self->render('entry.mt');
};

1;


__DATA__
@@ index.mt
<html>
<head>
<title>NoNoPaste: Yet Another NoPaste</title>
<link rel="stylesheet" type="text/css" href="<?= $req->uri_for('/static/js/prettify/prettify.css') ?>" />
<link rel="stylesheet" type="text/css" href="<?= $req->uri_for('/static/css/ui-lightness/jquery-ui-1.8.2.custom.css') ?>" />
<link rel="stylesheet" type="text/css" href="<?= $req->uri_for('/static/css/default.css') ?>" />
</head>
<body>
<div id="container">
<div id="header">
<h1 class="title"><a href="<?= $req->uri_for('/') ?>">NoNoPaste: Yet Another NoPaste</a></h1>
<div class="welcome">
<ul>
<li><a href="<?= $req->uri_for('/') ?>">TOP</a></li>
</ul>
</div>
</div>

<div id="content">

<h2 class="subheader">New Entry</h2>
<form method="post" action="/add" id="nopaste">
<textarea name="body" rows="20" cols="60"><?= defined $req->param('body') ? $req->param('body') : '' ?></textarea>

<label for="nick">nick</label>
<input type="text" id="nick" name="nick" value="<?= defined $req->param('nick') ? $req->param('nick') : '' ?>" size="21" />
<input type="submit" id="post_nopaste" value="POST" />
</form>

<h2 class="subheader">List</h2>

<? for my $entry ( @$entries ) { ?>
<div class="entry">
<pre class="prettyprint">
<?= $entry->{body} ?>
</pre>
<div class="entry_meta"><a href="<?= $req->uri_for('/entry/'.$entry->{id}) ?>" class="date"><?= $entry->{ctime} ?></a> / <span class="nick"><?= $entry->{nick} ?></span></div>
</div>
<? } ?> 

<p class="paging">
<? my $offset = $req->param('offset') || 0 ?>
<? if ( $offset >= 10 ) { ?>
<a href="<?= $req->uri_for('/', [ offset => ( $offset - 10 ) ] ) ?> ">Prev</a>
<? } ?>
<? if ( $next ) { ?>
<a href="<?= $req->uri_for('/', [ offset => ( $offset + 10 ) ] ) ?>">Next</a>
<? } ?>
</p>


</div>
</div>

<script src="<?= $req->uri_for('/static/js/jquery-1.4.2.min.js') ?>" type="text/javascript"></script>
<script src="<?= $req->uri_for('/static/js/jstorage.js') ?>" type="text/javascript"></script>
<script src="<?= $req->uri_for('/static/js/prettify/prettify.js') ?>" type="text/javascript"></script>
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
</body>
</html>


@@ entry.mt

<html>
<head>
<title>NoNoPaste: Yet Another NoPaste</title>
<link rel="stylesheet" type="text/css" href="<?= $req->uri_for('/static/js/prettify/prettify.css') ?>" />
<link rel="stylesheet" type="text/css" href="<?= $req->uri_for('/static/css/ui-lightness/jquery-ui-1.8.2.custom.css') ?>" />
<link rel="stylesheet" type="text/css" href="<?= $req->uri_for('/static/css/default.css') ?>" />
</head>
<body>
<div id="container">
<div id="header">
<h1 class="title"><a href="<?= $req->uri_for('/') ?>">NoNoPaste: Yet Another NoPaste</a></h1>
<div class="welcome">
<ul>
<li><a href="<?= $req->uri_for('/') ?>">TOP</a></li>
</ul>
</div>
</div>

<div id="content">
<h2 class="subheader"><a href="<?= $req->uri_for('/entry/'.$entry->{id}) ?>"><?= $req->uri_for('/entry/'.$entry->{id}) ?></a></h2>

<div class="entry">
<pre class="prettyprint">
<?= $entry->{body} ?>
</pre>
<div class="entry_meta"><a href="<?= $req->uri_for('/entry/'.$entry->{id}) ?>" class="date"><?= $entry->{ctime} ?></a> / <span class="nick"><?= $entry->{nick} ?></span></div>
</div>

</div>

</div>

<script src="<?= $req->uri_for('/static/js/jquery-1.4.2.min.js') ?>" type="text/javascript"></script>
<script src="<?= $req->uri_for('/static/js/jstorage.js') ?>" type="text/javascript"></script>
<script src="<?= $req->uri_for('/static/js/prettify/prettify.js') ?>" type="text/javascript"></script>
<script type="text/javascript">
$(function() {
    prettyPrint();
});
</script>
</body>
</html>