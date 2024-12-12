#!/usr/bin/perl
use 5.14.0;
use utf8;

use strict;
use warnings;
use JSON;

use Plack::Test;
use HTTP::Request::Common;
use Plack::Util;
use Test::More;
use DBI;

my $dir = '.';

BEGIN
{
    $dir = '.';
}

my $CFG = require "./conf/unit-app.conf";
state $dbh;

connect_db();
prepare_db();

################################################################################
sub connect_db
{
    $dbh //= DBI->connect_cached(
        $CFG->{ sql_dsn }, $CFG->{ sql_user }, $CFG->{ sql_pass },
        { RaiseError => 1, mysql_enable_utf8 => 1, mysql_multi_statements => 1, }
    );
    return $dbh;
}

sub prepare_db
{
    $dbh->do( "Delete from actions_v2" );
    $dbh->do( "Delete from coupon" );
    $dbh->do( "Delete from coupon_usage" );
    

    my $file = "$dir/sql/data.sql";

    my $sql_data = do {
        local $/ = undef;
        open my $fh, "<", $file
            or die "could not open $file: $!";
        <$fh>;
    };
    my $sth = $dbh->prepare("$sql_data");
    $sth->execute();
}

my $app    = Plack::Util::load_psgi 'psgi/coupon-img.psgi';
my $test   = Plack::Test->create( $app );
my $header = [ 'Content-Type' => 'application/json; charset=UTF-8' ];

sub test_resp {
    my ($uri, $answer, $text) = @_; 

    my $res = $test->request(
        GET $uri,
        Header  => $header,
    );
    
    is_deeply( decode_json( $res->content ), $answer, $text );
}

sub test_db {
    my $cnt_val = shift;
    my $cnt = $dbh->selectrow_array(
            "select count(*) from coupon 
            where action_id= 1",
        );
    
    is($cnt, $cnt_val, "У акции  $cnt_val купона");
}

test_resp(
   '/?cmd=bmp&actionId=1',
    {"value"=>"YXNkZg==\n",
     "type"=>"bmp"},
    "BMP ok"
);

test_resp(
   '/?cmd=bmp&actionId=11',
    {},
    "BMP unknown"
);

test_db(3);

test_resp(
   '/?cmd=genbmp&actionId=1',
    {"value"=>"YXNkZg==\n",
     "type"=>"bmp"},
    "gen BMP ok"
);

test_db(4);


done_testing;
