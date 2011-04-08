package NoNoPaste::Data;

use strict;
use warnings;
use utf8;
use parent qw/DBIx::Sunny::Schema/;
use Mouse::Util::TypeConstraints;
    
subtype 'Uint'
    => as 'Int'
    => where { $_ >= 0 };
    
no Mouse::Util::TypeConstraints;

__PACKAGE__->query(
    'add_entry',
    id => 'Str',
    nick => { isa => 'Str', default => 'anonymouse' },
    body => 'Str',
    q{INSERT INTO entries ( id, nick, body, ctime ) values ( ?, ?, ?, DATETIME('now') )},
);

__PACKAGE__->select_all(
    'entry_list',
    'offset' => { isa => 'Uint', default => 0 },
    q{SELECT id,nick,body,ctime FROM entries ORDER BY ctime DESC LIMIT ?,11}
);

__PACKAGE__->select_row(
    'retrieve_entry',
    'id' => 'Str',
    q{SELECT id,nick,body,ctime FROM entries WHERE id = ?}
);

1;

