#!/usr/bin/perl

#TODO: тесты на правильный подсчет лимитов по разным типам акции
use 5.14.0;
use utf8;

use strict;
use warnings;
use JSON;

use Plack::Test;
use HTTP::Request::Common;
use Plack::Util;
use Test::More;
use Test::Deep;
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

my $app    = Plack::Util::load_psgi 'psgi/personal-promo.psgi';
my $test   = Plack::Test->create( $app );
my $header = [ 'Content-Type' => 'application/json; charset=UTF-8' ];

my $action_5466 = {
    "aId"=>"3_7_5466",
    "cId"=>"7",
    "Привет Сидоров В."=>"Акция по карте 5466 1 применение на карту. Скидка 5%",};

my $action_121 = {
    "var1 1" => "Купон 121 для карты 0 по акции 1 2024-01-01 00:00:00 2030-01-01 00:00:00",
    "cId"=>"1",
    "aId"=>"1_1_0"};
my $coupon_answer_unknown  = [{
    "status"=>"unknown",
    "reason"=>"Not found",
    "action_id"=>0}];

############# getAction v1  ###################

test_resp(
    "/?cart=1&cardNumber=5466",
    [$action_5466],
    "getAction by card"
);

test_resp(
    "/?cart=1&cardNumber=121",
    [$action_121],
    "getAction by coupon"
);

############# getCoupon v1  ###################

test_resp(
    "/coupon?cart=1&cardNumber=5466",
    $coupon_answer_unknown,
    "getCoupon by card failed"
);


test_resp(
    "/coupon?cart=1&cardNumber=121",
    [{
        "status"=>"ok",
        "reason"=>"ok",
        "action_id"=>1,
        "action"=> $action_121
    }],
    "getCoupon by coupon"
);

############# getAction v2  ###################
my $answer = [
    {
        "action_id"=>1,
        "status"=>"ok",
        "action"=>{"aId"=>"1_1_5466","cId"=>"1", "var1 1"=>"Купон 121 для карты 5466 по акции 1 2024-01-01 00:00:00 2030-01-01 00:00:00"},
        "reason"=>"ok"
    },
    {
        "action"=>{
            "Привет Сидоров В."=>"Акция по карте 5466 1 применение на карту. Скидка 5%",
            "aId"=>"3_7_5466",
            "cId"=>"7"
        },
        "reason"=>"ok","action_id"=>3,"status"=>"ok"
    },
    {
      'status' => 'unknown',
      'action_id' => 4,
      'reason' => 'status[draft]'
    },
    {
      'status' => 'expired',
      'action_id' => 5,
      'reason' => re('end_date\[2024-01-30 00:00:00\] < now_date\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\]'),
    }
]; 

test_resp(
    "/v2/action?cart=1&cardNumber=5466&coupon=121",
    $answer,
    "getAction v2 by card & coupon"
);

############# карта + промокод  ###################
$answer = [
    {
        "action" => {
            "Привет Сидоров В."=>"Акция по карте 5466 1 применение на карту. Скидка 5%",
            "aId"=>"3_7_5466",
            "cId"=>"7"
        },
        "reason" => "ok","action_id"=>3,"status"=>"ok"
    },
    {
      'status' => 'unknown',
      'action_id' => 4,
      'reason' => 'status[draft]'
    },
    {
      'status' => 'expired',
      'action_id' => 5,
      'reason' => re('end_date\[2024-01-30 00:00:00\] < now_date\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\]'),
    },
    {
        "action_id" => 2,
        "status" => "ok",
        "action" => {
            "aId" => "2_4_5466",
            "cId" => "4",
            '5466' => "Промокод vmeste2024 2 применения на карту",
        },
        "reason" => "ok"
    },
]; 

test_resp(
    "/v2/action?cart=1&cardNumber=5466&coupon=vmeste2024",
    $answer,
    "getAction v2 by card & coupon"
);

############# карта + промокод потраченые ###################
$answer = [
    {
        "action_id" => 2,
        "status" => "invalid",
        "reason" => "action type[promocode]: cardNumber[1235] not defined or usage_cnt[1]>0"
    },
]; 

test_resp(
    "/v2/action?cart=1&cardNumber=1235&coupon=vmeste2024",
    $answer,
    "getAction v2 by card & coupon"
);

############# put ###################

my $res = $test->request(
    PUT '/?uniqKey=receipt10&receiptTS=2024-10-10&actionsId=1_1_5464&actionsId=2_4_5464&actionsId=3_6_5464',
    Header  => $header,
);

is ($res->content, "OK\n", 'put OK');
my $cnt = $dbh->selectrow_array(
            "select count(*) from coupon_usage
            where uniq_key='receipt10' and status='accepted' and card_number=5464 and coupon_id in(1,4,6) ",
        );
    
is($cnt, 3, "Coupon usage added");

############# put v2 ###################

my $res = $test->request(
    PUT '/v2?uniqKey=receipt11&cardNumber=5464&receiptTS=2024-10-10&couponId=1&couponId=4&couponId=6',
    Header  => $header,
);

is ($res->content, "OK\n", 'put v2 OK');
my $cnt = $dbh->selectrow_array(
            "select count(*) from coupon_usage
            where uniq_key='receipt11' and status='accepted' and card_number=5464 and coupon_id in(1,4,6) ",
        );
    
is($cnt, 3, "v2 Coupon usage added");
############# bind_cart ###################

$res = $test->request(
    PUT '/bind_cart?cart=cart10&cardNumber=5466&couponId=7&couponId=2&couponId=4',
    Header  => $header,
);

is ($res->content, "OK\n", 'put OK');
$cnt = $dbh->selectrow_array(
            "select count(*) from coupon_usage
            where uniq_key='cart10' and status='new' and card_number=5466 and coupon_id in(2,4,7) ",
        );
    
is($cnt, 3, "Bind for cart & actions added");


done_testing;

sub test_resp {
    my ($uri, $answer, $text) = @_; 

    my $res = $test->request(
        GET $uri,
        Header  => $header,
    );
    cmp_deeply( decode_json( $res->content ), $answer, $text );
}
