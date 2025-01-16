#!/usr/bin/perl
use 5.14.0;
use utf8;

use lib 'conf', 'lib';
use strict;
use warnings;
use JSON;

use Plack::Test;
use HTTP::Request::Common;
use Plack::Util;
use Test::More tests => 15;
use SmCh::DB qw(connect_db);

my $CFG = require "unit-app.conf";
my $dbh = connect_db( $CFG, { mysql_multi_statements => 1 } );

prepare_db();

sub prepare_db
{
    $dbh->do( "Delete from actions_v2" );
    $dbh->do( "Delete from coupon" );
    $dbh->do( "Delete from coupon_usage" );

    my $file     = "./sql/data.sql";
    my $sql_data = do {
        local $/ = undef;
        open my $fh, "<", $file
            or die "could not open $file: $!";
        <$fh>;
    };

    #print $sql_data;
    my $sth = $dbh->prepare( "$sql_data" );
    $sth->execute();
}

my $app    = Plack::Util::load_psgi 'psgi/holdout.psgi';
my $test   = Plack::Test->create( $app );
my $header = [ 'Content-Type' => 'application/json; charset=UTF-8' ];

my $uri = 'coupon-hold';
########## Holdout #################################

#error

my $data   = { "Unknown" => 1 };
my $answer = { "error"   => "cartId - обязательно. Одно из полей coupon или loyaltyCard - обязательно" };

test_resp( $uri, $data, $answer, "Error in params" );

#invalid (wrong cartId)
$data = {
    "cartId"      => 1,
    "loyaltyCard" => 5464,
    "coupon"      => 121
};
$answer = { %$data };
$answer->{ "status" } = "invalid";

test_resp( $uri, $data, $answer, "Coupon hold not succeed" );

#  ok - Holdout по купону и карте
$data->{ "cartId" } = 'cart1';

$answer = { %$data };
$answer->{ "status" } = "ok";

test_resp( $uri, $data, $answer, "Coupon hold succeed" );

my $cnt = $dbh->selectrow_array(
    "select count(*) from coupon_usage
        where uniq_key='cart1' and status='holdout' ",
);

is( $cnt, 2, "акции по купону и карте захолдированы" );

#todo

### Holdout по промокоду без карты
$data = {
    "cartId" => 'cart5',

    #"loyaltyCard" => 1235,
    "coupon" => 'vmeste2024'
};
$answer = {
    "cartId"      => 'cart5',
    "coupon"      => 'vmeste2024',
    "loyaltyCard" => undef,
    "status"      => "invalid"
};
test_resp( $uri, $data, $answer, "Promocode hold without card not succeed" );

### Holdout по промокоду без карты
$data->{ loyaltyCard }   = 1235;
$answer->{ loyaltyCard } = 1235;

test_resp( $uri, $data, $answer, "Promocode hold wrong card not succeed" );

### Holdout по промокоду успешный
$data->{ loyaltyCard }   = 1233;
$answer->{ loyaltyCard } = 1233;
$answer->{ status }      = 'ok';

test_resp( $uri, $data, $answer, "Promocode hold succeed" );

### Holdout не прошел по лимиту
$data->{ loyaltyCard }   = 1234;
$answer->{ loyaltyCard } = 1234;
$answer->{ status }      = 'invalid';

test_resp( $uri, $data, $answer, "Promocode hold out of limit not succeed" );

#TODO: проверить статус

###### Расхолдирование #################################################

### Unhold по купону
$uri = '/coupon-unhold';

#error

$data   = { "Unknown" => 1 };
$answer = { "error"   => "Одно из полей coupon или loyaltyCard - обязательно" };

test_resp( $uri, $data, $answer, "Unhold: Error in params " );

## Без cart:

$data   = { "coupon" => 122 };
$answer = {
    "cartId"      => undef,
    "coupon"      => 122,
    "loyaltyCard" => undef,
    "status"      => "ok"
};

test_resp( $uri, $data, $answer, "Unhold without cart succeed " );

#Две корзины c holdout и card_number=0 для одного купона
$data   = { "coupon" => 123 };
$answer = { "error" => "Купон захолдирован несколько раз, не удается выбрать корзину"};

test_resp( $uri, $data, $answer, "Unhold without cart  not succeed when two carts holded" );

#invalid
$data = {
    "cartId"      => 1,      #wrong
    "loyaltyCard" => 5464,
    "coupon"      => 121
};

$answer = { %$data };
$answer->{ status } = 'invalid';

test_resp( $uri, $data, $answer, "Coupon  unhold not succeed" );

#TODO нужны тесты:
# неуспешно-  когда передана неверная карта для промокода или

#ok
$data->{ "cartId" } = 'cart1';
$answer             = { %$data };
$answer->{ status } = 'ok';

test_resp( $uri, $data, $answer, "Coupon  unhold succeed" );

#TODO: check status

# промокоды
$data = {
    "cartId" => 'cart5',       #wrong
    "coupon" => "vmeste2024"
};

$answer                  = { %$data };
$answer->{ loyaltyCard } = undef;
$answer->{ status }      = 'invalid';

test_resp( $uri, $data, $answer, "Promocode unhold unsucceed with unknown card" );

$data->{ loyaltyCard }   = 1233;
$answer->{ loyaltyCard } = 1233;
$answer->{ status }      = 'ok';

test_resp( $uri, $data, $answer, "Promocode unhold succeed" );

sub test_resp {
    my ( $uri, $data, $answer, $text ) = @_;

    my $res = $test->request(
        POST $uri,
        Header  => $header,
        Content => encode_json( $data )
    );
    is_deeply( decode_json( $res->content ), $answer, $text );
}

done_testing;
