package SmCh::DB;

use 5.14.0;
use DBI;

use base 'Exporter';
our @EXPORT_OK = qw(connect_db);

state $dbh;

sub connect_db
{
    my $CFG = shift;
    my $opt = shift // {};

    $dbh = DBI->connect(
        $CFG->{ sql_dsn }, $CFG->{ sql_user }, $CFG->{ sql_pass },
        { RaiseError => 1, mysql_enable_utf8 => 1, %$opt }
    );
    return $dbh;
}

1;
