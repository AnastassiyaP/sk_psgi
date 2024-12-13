use 5.14.0;
use strict;
use warnings;
use utf8;

my $dir;

BEGIN
{
    $dir = $0;
    $dir =~ s{/[^/]+$}{};
}

use lib 'conf', 'lib', 'lib/perl', "$dir/lib", "$dir/lib/perl";

use Plack::Builder;
use Plack::Request;
use Carp;
use JSON::XS;
use SFE::Logger::Stderr2;
use ShopBrand qw(
    checkShopIdsByAddr
);

use DB;
use Const;

my $CFG = do "unit-app.conf";

SFE::Logger::Stderr2->level( $CFG->{ log_level } // 'warning' );

#список работающих акций по cardNumber или code

# promocode - 2 лимита: 1 применение по карте и общий лимит на к-во карт
# coupon - Лимит применений на купон без привязки к карте 
# card - лимит на карту 
my $SQL_actionByCardNumber_v2 = <<SQL;
SELECT c.action_id,
    c.id as coupon_id,
    c.code,
    a.type,
    placeholders,
    action_body,
    addr,
    IFNULL(c.start_date, a.start_date) as start_date,
    IFNULL(c.end_date, a.end_date) as end_date,
    a.limit,
    (
        SELECT count(*)
        FROM coupon_usage
        WHERE coupon_id = c.id
          AND coupon_usage.status in('holdout','accepted')
    ) AS usage_cnt,
    (
        SELECT count(*)
        FROM coupon_usage
        WHERE coupon_id = c.id
          AND coupon_usage.status in('holdout','accepted')
          AND coupon_usage.card_number = ?
    ) AS usage_cnt_card,
    a.status,
    NOW() AS now_date
FROM coupon c
JOIN actions_v2 a ON a.id=c.action_id 
WHERE c.code IN (%s)
SQL

#список работающих акций по cardNumber или code
# card - лимит на карту
# coupon - лимит на купон без учета карты
my $SQL_actionByCardNumber = <<SQL;
SELECT c.action_id,
    c.id as coupon_id,
    c.code,
    a.type,
    placeholders,
    action_body,
    addr,
    IFNULL(c.start_date, a.start_date) as start_date,
    IFNULL(c.end_date, a.end_date) as end_date
FROM coupon c
JOIN actions_v2 a ON a.id=c.action_id 
WHERE c.code = ?
AND a.type in ('coupon', 'card')
AND a.status = 'run'
AND a.start_date <= NOW()
AND NOW() < a.end_date
AND (`limit` = 0
    OR (`limit` > (
        SELECT count(*)
        FROM coupon_usage
        WHERE coupon_id = c.id
          AND coupon_usage.status in('holdout','accepted'))
    ))
SQL

#Купоны по коду
my $SQL_actionByCoupon = <<SQL;
SELECT c.action_id,
    c.id as coupon_id,
    c.code,
    placeholders,
    action_body,
    addr,
    IFNULL(c.start_date, a.start_date) as start_date,
    IFNULL(c.end_date, a.end_date) as end_date,
    a.`limit`,
    a.type,
    (
        SELECT count(*)
        FROM coupon_usage
        WHERE coupon_id = c.id
          AND coupon_usage.status in('holdout','accepted')
    ) AS usage_cnt,
    a.status,
    NOW() AS now_date

FROM coupon c
JOIN actions_v2 a ON a.id=c.action_id 
WHERE c.code = ?
AND a.type = 'coupon'
SQL

my $SQL_add_coupon_usage = <<SQL;
INSERT INTO coupon_usage
    (coupon_id, card_number, uniq_key, shop_id, status, receipt_ts)
    VALUES %s
SQL

my $app = sub {
    my $env = shift;

    my $self = __PACKAGE__->new_new_new( env => $env );

    my $debug = $self->{ params }->{ debug };
    $debug && ( local $SFE::Logger::LOG_LEVEL = LOG_LEVEL_DEBUG );
    if ( $debug ) {
        my %self = %$self;
        delete $self{ dbh };
        delete $self{ req };
        delete $self{ env };
        Debugf( "SELF %s", \%self );
    }

    if ( $self->{ method } eq "GET" )
    {
        if ( $self->{ path_info } =~ m{/coupon$} ) {
            $self->getCoupon();
        }
        elsif ( $self->{ path_info } =~ m{/v2/action$} ) {
            $self->getAction_v2();
        }
        else {
            $self->getAction();
        }
    }
    elsif ( $self->{ method } eq "PUT" )
    {
        if ( $self->{ path_info } =~ m{/v2} ) {
            $self->put_v2();
        } elsif($self->{path_info } =~m{/bind_cart} ) {
            #TODO
            $self->bind_cart_actions();
        }
        else {
            $self->put();
        }
    }
    else
    {
        Warning( "Unknown method[$self->{ method }]" );
    }
};

builder
{
    enable 'ContentLength';
    $app;
};

################################################################################
sub new_new_new {
    my $class = shift;
    my $self  = bless {}, $class;

    %$self = ( %$self, @_ );
    my $req    = Plack::Request->new( $self->{ env } );
    my $params = $req->query_parameters();

    $self->{ req }       = $req;
    $self->{ params }    = $params;
    $self->{ method }    = $req->method();
    $self->{ path_info } = $req->path_info();
    $self->{ dbh }       = connect_db($CFG);
    
    state $shop_map = {
        'IA' => IA_SHOP_ID,
        'undef' => 0,
    };


    my $trade = $params->{ trade };
    if ( $trade ) {
        $self->{ shop_id } = ( exists $shop_map->{ $trade } ) ?
            $shop_map->{ $trade } :
            $trade =~ s/^TM//ir;
    }

    return $self;
}
################################################################################
### ядро и хаб ####
sub getAction
{
    my $self = shift;

    my $params = $self->{ params };

    my $cardNumber = $params->{ cardNumber };#карта или купон
    my $cart       = $params->{ cart };

    my $sth = $self->{ dbh }->prepare( $SQL_actionByCardNumber );
    $sth->execute( $cardNumber  );
    my @answer;
    my @couponId;
    
    my $card = 0;
    
    while (my $res = $sth->fetchrow_hashref )
    {
        if ($res->{type} eq 'card') {
            $card = $cardNumber;
        }
        $self->check_addr( $res->{ addr } ) or next;

        push @couponId, $res->{ coupon_id };
        my $action = $self->prepareAction(
            $card,
            $res
        );
        push @answer, $action;
    }
    $sth->finish();

    # Связываем корзину ИА, номер карты/купона и id акции
    if ( $cart && scalar @couponId  ) {
        $self->add_coupon_usage( $cart, $card, \@couponId );
    }

    my $response = $self->{ req }->new_response( 200 );
    $response->body( encode_json( \@answer ) );
    return $response->finalize();
}
################################################################################
### только ядро
sub getCoupon
{
    my $self = shift;

    my $params = $self->{ params };

    my $coupon = $params->{ cardNumber }; #только купон
    my $cart   = $params->{ cart };
    my $card   = 0;

    my @couponIdToBind;
    my @answer;

    my $sth = $self->{ dbh }->prepare( $SQL_actionByCoupon );
    $sth->execute( $coupon );
    

    while ( my $res = $sth->fetchrow_hashref )
    {
        Debugf("Find action %s", $res );
        my ( $status, $reason ) = $self->couponStatus( $res );
        my $answer = {
            status    => $status,
            action_id => $res->{ action_id },
            reason    => $reason,
        };
        push @answer, $answer;

        if ( $status eq STATUS_OK ) {
            push @couponIdToBind, $res->{ coupon_id };
            my $action = $self->prepareAction( $card, $res );
            $answer->{ action } = $action;
        }
    }
    $sth->finish();

    unless ( @answer ) {
        Debug "Actions not found. cardNumber[$coupon]";
        push @answer, {
            action_id => 0,
            status    => STATUS_UNKNOWN,
            reason    => "Not found",
        };
    }
    # Связываем корзину ИА, номер карты/купона и id акции
    if ( $cart && @couponIdToBind ) {
        $self->add_coupon_usage( $cart, $card, \@couponIdToBind );
    }

    my $res = $self->{ req }->new_response( 200 );
    $res->body( encode_json( \@answer ) );
    return $res->finalize();
}
################################################################################
sub getAction_v2
{
    my $self = shift;
    my $params = $self->{ params };

    my $cardNumber = $params->{ cardNumber };#карта
    my $cart       = $params->{ cart };

    my @couponCode     = $params->get_all( "coupon" );
    push @couponCode, $cardNumber;

    my $qmarks = join(',', ('?') x @couponCode);

    my $SQL = sprintf($SQL_actionByCardNumber_v2, $qmarks);

    my $sth = $self->{ dbh }->prepare( $SQL );
    $sth->execute( $cardNumber, @couponCode );

    my @answer;
    my @couponId;
    
    my $res;
    while ( $res = $sth->fetchrow_hashref )
    {
        $self->check_addr( $res->{ addr } ) or next;
        my ( $status, $reason ) = $self->couponStatus( $res, $cardNumber );
        my $answer = {
            status    => $status,
            action_id => $res->{ action_id },
            reason    => $reason,
        };
        push @answer, $answer;

        if ( $status eq STATUS_OK ) {
            push @couponId, $res->{ coupon_id };
            my $action = $self->prepareAction( $cardNumber, $res);
            $answer->{ action } = $action;
        }
    }
    $sth->finish();

    my $response = $self->{ req }->new_response( 200 );
    $response->body( encode_json( \@answer ) );
    return $response->finalize();
}
################################################################################
sub put
{
    my $self = shift;
    my $dbh  = $self->{ dbh };

    my $params = $self->{ params };
    
    my $uniq_key   = $params->{uniqKey};
    my $receipt_ts = $params->{receiptTS};
    my @actionsId  = $params->get_all( "actionsId" );
    
    unless ( $uniq_key && defined $receipt_ts && scalar @actionsId){
        my $res = $self->{ req }->new_response( 400 );
        $res->headers( [ 'Content-Type' => 'application/json' ] );

        $res->body(encode_json(
            {"error"=> "Необходимые аргументы для сохранения записи: uniqKey, receiptTS, actionsId"
             }
        ));
        return $res->finalize();
    }
    
    my @couponId;
    my ( $action_id, $coupon_id, $card_number );
    foreach ( @actionsId )
    {
        ( $action_id, $coupon_id, $card_number ) = split "_";
        push @couponId, $coupon_id;
    }
    $self->add_coupon_usage(
        $uniq_key,
        $card_number,
        \@couponId,
        'accepted',
        $self->{shop_id} // 0,
        $receipt_ts,
    );

    my $res = $self->{ req }->new_response( 200 );
    $res->body( "OK\n" );
    return $res->finalize();
}
################################################################################
# метод от хаба
# TODO: дообсудить с Денисом, либо убрать совсем, либо получать список @couponId вместо actions 
sub put_v2
{
    my $self = shift;
    my $dbh  = $self->{ dbh };

    my $params = $self->{ params };

    my $uniq_key   = $params->{uniqKey};
    my $cardNumber = $params->{cardNumber};
    my $receipt_ts = $params->{receiptTS};
    my @couponId   = $params->get_all( "couponId" );
    
    unless ( $uniq_key && defined $receipt_ts && scalar @couponId){
        my $res = $self->{ req }->new_response( 400 );
        $res->headers( [ 'Content-Type' => 'application/json' ] );
        $res->body(encode_json(
            {"error"=> "Необходимые аргументы для сохранения записи: uniqKey, receiptTS, couponId"}
        ));
        return $res->finalize();
    }
    $self->add_coupon_usage(
        $uniq_key,
        $cardNumber,
        \@couponId,
        'accepted',
        $self->{shop_id} // 0,
        $receipt_ts,  );

    my $res = $self->{ req }->new_response( 200 );
    $res->body( "OK\n" );
    return $res->finalize();
}


################################################################################
# Метод от Ядра
# Связывает фактически примененные акции с корзиной
sub bind_cart_actions{
    my $self = shift;

    my $params = $self->{ params };

    my $cardNumber = $params->{ cardNumber };#карта
    my $cart       = $params->{ cart };
    my @couponId   = $params->get_all( "couponId" );

    $self->add_coupon_usage(
        $cart,
        $cardNumber,
        \@couponId, 'new', $self->{shop_id} // 0, undef,
    );
    my $res = $self->{ req }->new_response( 200 );
    $res->body( "OK\n" );
    return $res->finalize();

}

################################################################################
#Подставляет в actions.action_body значения из card_action.placeholders и предопределенные из базы.
# формирует итоговый json с акцией 
sub prepareAction {
    my $self        = shift;
    my $cardNumber  = shift;
    my $card_action = shift;
    utf8::encode($card_action->{ placeholders });
    my $placeholders = decode_json($card_action->{ placeholders }|| '{}');
    
    $placeholders->{CARD_NUMBER}   = $cardNumber;
    $placeholders->{COUPON_NUMBER} = $card_action->{code};
    $placeholders->{ACTION_ID}     = $card_action->{action_id};
    $placeholders->{START_DATE}    = $card_action->{start_date};
    $placeholders->{END_DATE}      = $card_action->{end_date};
    #Errf("  action body %s", $action_body);

    my $action_body = $card_action->{ action_body };
    $action_body =~ s/%%%(\w+)%%%/$placeholders->{$1}/ge;
    
    my $action = decode_json( $action_body );
    if ( $action->{ aId } && $action->{ aId } =~ /^[0-9]+$/ )
    {
        $action->{ aId } .= "_$card_action->{coupon_id}_$cardNumber";
    }
    else {
        $action->{ aId } = "$card_action->{action_id}_$card_action->{coupon_id}_$cardNumber";
    }

    $action->{ cId } = $card_action->{coupon_id};
    
    return $action;
}

################################################################################
#    action             "{\"aId\": 3144 ...........}",
#    action_id          3144,
#    addr               "{\"all\": false, \"brands\": [], \"values\": [], \"macrobrands\": [\"33\", \"31\", \"32\"]}",
#    disc_count         0,
#    disc_count_limit   1,
#    end_date           "2025-03-18 23:59:59" (dualvar: 2025),
#    id                 1157590462,
#    now_date           "2024-03-23 16:39:41" (dualvar: 2024),
#    start_date         "2024-03-18 00:00:00" (dualvar: 2024),
#    status             "run"

#TODO добавить условие про карту для промокода
#двойной лимит для карты
sub couponStatus {
    my $self = shift;
    my $arg  = shift;
    my $cardNumber = shift;

    my $disc_count_limit = $arg->{ limit };
    my $disc_count       = $arg->{ disc_count };
    my $disc_count_card       = $arg->{ disc_count_card };

    # invalid - купон был использован и погашен ранее
    if (
        $arg->{type} =~ /^(?:coupon|promocode)$/ and
        $arg->{limit} and
        $arg->{limit} <= $arg->{usage_cnt}) {
        return (STATUS_INVALID,
            "action type[$arg->{type}]: limit[$arg->{limit}] <= usage_cnt[$arg->{usage_cnt}]"
                );
    }
    if ($arg->{type} eq 'card' and 
        $arg->{limit} and $arg->{limit} <= $arg->{usage_cnt_card}){
        return (STATUS_INVALID,
            "action type[$arg->{type}]: limit[$arg->{limit}] <= usage_cnt[$arg->{usage_cnt_card}]"
                );
    }
    if (
        $arg->{type} eq 'promocode' and
        (!$cardNumber or $arg->{usage_cnt_card}>0)){
        return (STATUS_INVALID,
            "action type[$arg->{type}]: cardNumber[$cardNumber] not defined or usage_cnt[$arg->{usage_cnt_card}]>0"
                );
    }

    my $end_date = $arg->{ end_date };
    my $now_date = $arg->{ now_date };

    if ( $end_date lt $now_date ) {
        return (
            STATUS_EXPIRED,
            "end_date[$end_date] < now_date[$now_date]"
        );
    }

    if ( $arg->{ status } ne 'run' ) {
        return (
            STATUS_UNKNOWN,
            "status[$arg->{ status }]"
        );
    }

    my $start_date = $arg->{ start_date };

    if ( $now_date lt $start_date ) {
        return (
            STATUS_FAIL,
            "now_date[$now_date] < start_date[$start_date]"
        );
    }

    unless ( $self->check_addr( $arg->{ addr } ) ) {
        return (
            STATUS_FAIL,
            "check_addr() - false"
        );
    }

    return (
        STATUS_OK,
        "ok"
    );
}

################################################################################
sub add_coupon_usage
{
    my $self        = shift;
    my $cart        = shift;
    my $cardNumber  = shift;
    my $couponIdArr = shift;
    my $status      = shift;
    my $shop_id      = shift;
    my $receipt_ts   = shift;
    
    my $dbh = $self->{ dbh };
    
    $status //= 'new';
    $shop_id //= 0;
    $dbh->do("DELETE FROM coupon_usage where uniq_key=? ",undef,$cart);

    my $qmarks = join(',', ('(?,?,?,?,?,?)') x @$couponIdArr);
    my $sql = sprintf($SQL_add_coupon_usage, $qmarks);

    my @values = map {
        $_, $cardNumber, $cart, $shop_id, $status, $receipt_ts
    } @$couponIdArr;

    $dbh->do( $sql, undef, @values );
    return;
}
################################################################################
sub check_addr {
    my $self     = shift;
    my $addrJson = shift;
    my $shop_id = $self->{ shop_id };

    # Если $shop_id или $addrJson не задан, то не ограничиваем по адресу
    ($shop_id and $shop_id ne IA_SHOP_ID)
        or return 1;
    defined $addrJson or return 1;

    my $addr = decode_json( $addrJson );

    # Если все, то дальше смотреть не нужно
    $addr->{ all } && return 1;
    
    return checkShopIdsByAddr( $self->{ dbh }, $shop_id, $addr );
}

################################################################################
