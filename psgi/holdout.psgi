use 5.14.0;
use strict;
use warnings;

my $dir;

BEGIN
{
    $dir = $0;
    $dir =~ s{/[^/]+$}{};
}

use lib 'lib', "$dir/lib", "lib/perl";

use Plack::Builder;
use Plack::Request;
use DBI;
use Carp;
use JSON::XS;
use SFE::Logger::Stderr2;
use ShopBrand qw(
    checkShopIdsByAddr
);

# ok      - Можно применять
# fail    - не соблюдены условия промоакции
# unknown - купон не зарегистрирован в SmartCheckout
# expired - купон принадлежит завершившейся промоакции
# invalid - купон был использован и погашен ранее
#
use constant STATUS_OK      => 'ok';
use constant STATUS_FAIL    => 'fail';
use constant STATUS_UNKNOWN => 'unknown';
use constant STATUS_EXPIRED => 'expired';
use constant STATUS_INVALID => 'invalid';
use constant STATUS_HOLDOUT => 'holdout';

use constant IA_SHOP_ID => 10 ** 6 # интернет аптека;
my $CFG = require "$dir/unit-app.conf";

SFE::Logger::Stderr2->level( $CFG->{ log_level } // 'debug' );


my $SQL_add_card_usage = <<SQL;
   INSERT INTO `card_usage`(
    uniq_key,
    receipt_ts,
    action_id,
    card_number,
    shop_id,
    status)
   values(?,?,?,?,?,?)
SQL


my $SQL_actionByCoupon = <<SQL;
   SELECT `card_action`.action_id,
          `card_action`.placeholders,
          actions.action_body,
          `actions`.addr,
          actions.limit,
          (select count(*) from card_usage where card_number = card_action.card_number) as disc_count,
          actions.start_date,
          actions.end_date,
          actions.status,
          NOW() AS now_date
   FROM `card_action`
   JOIN `actions_v2` actions  ON (`card_action`.action_id = `actions`.id)
   WHERE card_number = ?
SQL


my $app = sub {
    my $env = shift;

    my $request = Plack::Request->new( $env );
    my $params = $request->query_parameters();


    if ( $request->method() eq "PUT" &&
        $req->path_info() =~ m{/holdout$} )
    {
        return holdout($request, $params);
    }

    Warning( "Unknown method[$self->{ method }]" );

    my $res = $request->new_response( 404 );
    return $res->finalize();
};

builder
{
    enable 'ContentLength';
    $app;
};
################################################################################
sub holdout
{
    my ($request, $params) = @_;
    # TODO:
    # проверка карты по акции, а не купона
    # проверка что купон можно применить
    # проверка корзины в ia_cart_card
    # что делать с receiptTS и uniqKey
    #
        
    params:
    actionId
    cardNumber
    couponNumber
    uniqKey
    receiptTS
    
    my $dbh = connect_db();

    #my $cardNumber = $params->{ cardNumber };
    my $coupon = $params->{ coupon };
    my $cart   = $params->{ cartId };
    
    
    my $row = $dbh->selectrow_hashref( "select card_number from ia_cart_card where coupon_id=$coupon and cart=$cart" );
    my $card_number = $row->{card_number};
    
    return fail($coupon, $cart) unless $card_number;
    
    my $action = $dbh->selectrow_hashref("SELECT *
       FROM coupon c
       JOIN action_v2 a on c.action_id=a.id
        
       WHERE c.code=$coupon
       AND a.status = 'run'
       AND a.start_date <= NOW()
       AND NOW() < a.end_date
    ");
    
    return fail($coupon, $cart) unless $action;
    
    # TODO может ли быть задан лимит типа - 5 применений купона на карту?
    # или лимит всегда только на коллличество карт
    
    # в какой ситуа
    my $coupon_usage = $dbh->selectrow_hashref("
    select status, count(*) as cnt from coupon_usage
    where coupon_id = $coupon_id
    and status in('holdout','accepted') and card_number=$card_number");
    
    $coupon_usage == 1
        or return fail($coupon, $cart); 
    
    
    

-- количество использований вообще
select count(*) from coupon_usage
where coupon_id = $coupon_id
and status in('holdout','accepted')

-- количество использований с этой картой 



 
    
    unless ( $uniq_key && defined $receipt_ts && scalar @actionsId){
        my $res = $self->{ req }->new_response( 400 );
        $res->body( "Необходимые аргументы для сохранения записи: uniqKey, receiptTS, actionsId" );
        return $res->finalize();
    }
    
    foreach ( @actionsId )
    {
        my ( $action_id, $card_number ) = split "_";
        $dbh->do(
            $SQL_add_card_usage,
            undef, $uniq_key,
            $receipt_ts,
            $action_id,
            $card_number,
            IA_SHOP_ID,
            'holdout'
            )
            or die "Can't update mysql: " . $dbh->err . " (" . $dbh->errstr . ")";
    }

    my $res = $self->{ req }->new_response( 200 );
    $res->body( "OK\n" );
    return $res->finalize();
}
################################################################################
sub connect_db
{
    state $dbh;
    $dbh //= DBI->connect_cached(
        $CFG->{ sql_dsn }, $CFG->{ sql_user }, $CFG->{ sql_pass },
        { RaiseError => 1, mysql_enable_utf8 => 1 }
        )
        or die "Can't connect to MySQL: $DBI::err ($DBI::errstr)";
    return $dbh;
}
################################################################################
