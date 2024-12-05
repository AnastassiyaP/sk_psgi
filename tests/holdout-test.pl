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
    #open my $fh, "<", $file
    #    or die "could not open $file: $!";
    #while my $line (<$fh>){
    #    if $line =~/^\w/
    #    $dbh->do($_);
    #}
    my $sql_data = do {
        local $/ = undef;
        open my $fh, "<", $file
            or die "could not open $file: $!";
        <$fh>;
    };
    #print $sql_data;
    my $sth = $dbh->prepare("$sql_data");
    $sth->execute();
}

my $app    = Plack::Util::load_psgi 'psgi/holdout.psgi';
my $test   = Plack::Test->create( $app );
my $header = [ 'Content-Type' => 'application/json; charset=UTF-8' ];

### Holdout 

#error

my $data = { "Unknown" => 1 };

my $res = $test->request(
    POST "/coupon-hold",
    Header  => $header,
    Content => encode_json( $data )
);

my $answer = { "error" => "cartId - обязательно. Одно из полей coupon или loyaltyCard - обязательно" };

is_deeply( decode_json( $res->content ), $answer, "Error in params" );

#invalid (wrong cartId)
$data = {
    "cartId"      => 1,
    "loyaltyCard" => 5464,
    "coupon"      => 121
};
$res                  = $test->request( POST "/coupon-hold", Header => $header, Content => encode_json( $data ) );
$answer               = { %$data };
$answer->{ "status" } = "invalid";
is_deeply( decode_json( $res->content ), $answer, "Coupon hold not succeed" );


#  ok - Holdout по купону и карте
$data->{ "cartId" }   = 'cart1';
$res          = $test->request( POST "/coupon-hold", Header => $header, Content => encode_json( $data ) );

$answer = {%$data};
$answer->{"status"} = "ok";


is_deeply( decode_json( $res->content ), $answer, "Coupon hold succeed" );
my $cnt = $dbh->selectrow_array(
        "select count(*) from coupon_usage
        where uniq_key='cart1' and status='holdout' ",
    );

is($cnt,2,"акции по купону и карте захолдированы");

#todo

### Holdout по промокоду без карты
$data = {
    "cartId"      => 'cart5',
    #"loyaltyCard" => 1235,
    "coupon"      => 'vmeste2024'
};
$res    = $test->request( POST "/coupon-hold", Header => $header, Content => encode_json( $data ) );
$answer = {
    "cartId"      => 'cart5',
    "coupon"      => 'vmeste2024',
    "loyaltyCard" => undef,
    "status"      => "invalid"
};
is_deeply( decode_json( $res->content ), $answer, "Promocode hold without card not succeed" );

### Holdout по промокоду без карты
$data->{loyaltyCard} = 1235;
$answer->{loyaltyCard} = 1235;

$res    = $test->request( POST "/coupon-hold", Header => $header, Content => encode_json( $data ) );
is_deeply( decode_json( $res->content ), $answer, "Promocode hold wrong card not succeed" );

### Holdout по промокоду успешный
$data->{loyaltyCard} = 1233;
$answer->{loyaltyCard} = 1233;
$answer->{status} = 'ok';

$res    = $test->request( POST "/coupon-hold", Header => $header, Content => encode_json( $data ) );
is_deeply( decode_json( $res->content ), $answer, "Promocode hold succeed" );

### Holdout не прошел по лимиту
$data->{loyaltyCard} = 1234;
$answer->{loyaltyCard} = 1234;
$answer->{status} = 'invalid';

$res    = $test->request( POST "/coupon-hold", Header => $header, Content => encode_json( $data ) );
is_deeply( decode_json( $res->content ), $answer, "Promocode hold out of limit not succeed" );
#TODO: проверить статус


########################################################################
###### Расхолдирование #################################################

### Unhold по купону

#error

$data = { "Unknown" => 1 };

$res = $test->request(
    POST "/coupon-unhold",
    Header  => $header,
    Content => encode_json( $data )
);

$answer = { "error" => "Одно из полей coupon или loyaltyCard - обязательно" };

is_deeply( decode_json( $res->content ), $answer, "Unhold: Error in params" );


## Без cart:

$data = {
    "coupon"      => 122
};
$answer = {
    "cartId"      => undef,
    "coupon"      => 122,
    "loyaltyCard" => undef,
    "status"      => "ok"
};

$res = $test->request(
    POST "/coupon-unhold",
    Header  => $header,
    Content => encode_json( $data )
);

is_deeply( decode_json( $res->content ), $answer, "Unhold without cart succeed " );

#Две корзины c holdout и card_number=0 для одного купона 
$data = {
    "coupon"      => 123
};
$answer = {
    "error" => "Захолдиновано несколько купонов, не удается выбрать корзину" };

$res = $test->request(
    POST "/coupon-unhold",
    Header  => $header,
    Content => encode_json( $data )
);

is_deeply( decode_json( $res->content ), $answer, "Unhold without cart unsucceed when two carts holded" );


#invalid
$data = {
    "cartId"      => 1, #wrong
    "loyaltyCard" => 5464,
    "coupon"      => 121
};

$res = $test->request(
    POST "/coupon-unhold",
    Header  => $header,
    Content => encode_json( $data )
);

$answer =  {%$data};
$answer->{status}='invalid';

is_deeply( decode_json( $res->content ), $answer, "Coupon unhold not succeed" );

#TODO нужны тесты:
# неуспешно-  когда передана неверная карта для промокода или 



#ok
$data->{ "cartId" }      = 'cart1';
$answer = {%$data};

$res = $test->request(
    POST "/coupon-unhold",
    Header  => $header,
    Content => encode_json( $data )
);

$answer->{status} = 'ok';

is_deeply( decode_json( $res->content ), $answer, "Coupon unhold succeed" );
#TODO: check status


# промокоды

$data = {
    "cartId"      => 'cart5', #wrong
    #"loyaltyCard" => 1222,
    "coupon"      => "vmeste2024"
};

$answer = {%$data};
$answer->{loyaltyCard} = undef;
$answer->{status} = 'invalid';

$res = $test->request(
    POST "/coupon-unhold",
    Header  => $header,
    Content => encode_json( $data )
);
is_deeply( decode_json( $res->content ), $answer, "Promocode unhold unsucceed with unknown card" );


$data->{loyaltyCard}= 1233;
$answer->{loyaltyCard}= 1233;
$answer->{status} = 'ok';

$res = $test->request(
    POST "/coupon-unhold",
    Header  => $header,
    Content => encode_json( $data )
);
is_deeply( decode_json( $res->content ), $answer, "Promocode unhold succeed" );

done_testing;
