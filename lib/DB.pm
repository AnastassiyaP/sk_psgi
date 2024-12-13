package DB;

use 5.14.0;
use DBI;

use base 'Exporter';
our @EXPORT = qw(connect_db);

state $dbh;
sub connect_db
{
    my $CFG = shift;
    my $opt = shift // {};

    $dbh = DBI->connect_cached(
        $CFG->{ sql_dsn }, $CFG->{ sql_user }, $CFG->{ sql_pass },
        { RaiseError => 1, mysql_enable_utf8 => 1, %$opt }
        )
        or die "Can't connect to MySQL: $DBI::err ($DBI::errstr)";
    return $dbh;
}

1;