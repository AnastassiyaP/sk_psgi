use 5.14.0;
use strict;
use warnings;

my $dir;

BEGIN
{
    $dir = $0;
    $dir =~ s{/[^/]+$}{};
}

use lib 'lib', "$dir/lib";

use Plack::Builder;
use Plack::Request;
use DBI;
use Carp;
use JSON::XS;
use SFE::Logger::Stderr;
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

use constant IA_SHOP_ID => 10 ** 6;
my $CFG = require "$dir/unit-app.conf";

SFE::Logger->level( $CFG->{ log_level } // 'warning' );

my $SQL_actionByCardNumber = <<SQL;
   SELECT `card_action`.action_id,
     placeholders, action_body, actions.addr,
     actions.start_date,
     actions.end_date

   FROM `card_action`
   JOIN `actions_v2` actions  ON (`card_action`.action_id = `actions`.id)
   WHERE card_number = ?
     AND `actions`.status = 'run'
     AND actions.start_date <= NOW()
     AND NOW() < actions.end_date
     AND ( `limit` = 0 OR (select count(*) from card_usage where card_number = card_action.card_number) <= `limit` ) 
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

my $SQL_add_card_usage = <<SQL;
   INSERT INTO `card_usage`(uniq_key, receipt_ts, action_id, card_number, shop_id)
   values(?,?,?,?,?)
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
        else {
            $self->getAction();
        }
    }
    elsif ( $self->{ method } eq "PUT" )
    {
        $self->put();
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
    $self->{ dbh }       = connect_db();
    
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
sub getAction
{
    my $self = shift;

    my $params = $self->{ params };

    my $cardNumber = $params->{ cardNumber };
    my $cart       = $params->{ cart };

    my $sth = $self->{ dbh }->prepare( $SQL_actionByCardNumber );
    $sth->execute( $cardNumber );
    my @answer;
    my @actionId;
    while ( my $res = $sth->fetchrow_hashref )
    {
        $self->check_addr( $res->{ addr } ) or next;

        push @actionId, $res->{ action_id };
        my $action = $self->prepareAction(
            $cardNumber,
            $res
        );
        push @answer, $action;
    }
    $sth->finish();

    # Связываем корзину ИА, номер карты/купона и id акции
    if ( $cart && @actionId ) {
        $self->bind_cart_card( $cart, $cardNumber, \@actionId );
    }

    my $res = $self->{ req }->new_response( 200 );
    $res->body( encode_json( \@answer ) );
    return $res->finalize();
}
################################################################################
sub getCoupon
{
    my $self = shift;

    my $params = $self->{ params };

    my $cardNumber = $params->{ cardNumber };
    my $cart       = $params->{ cart };

    my @actionIdToBind;
    my @answer;
    my $sth = $self->{ dbh }->prepare( $SQL_actionByCoupon );
    $sth->execute( $cardNumber );
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
            push @actionIdToBind, $res->{ action_id };
            my $action = $self->prepareAction( $cardNumber, $res );
            $answer->{ action } = $action;
        }
    }
    $sth->finish();

    unless ( @answer ) {
        Debug "Actions not found. cardNumber[$cardNumber]";
        push @answer, {
            action_id => 0,
            status    => STATUS_UNKNOWN,
            reason    => "Not found",
        };
    }

    # Связываем корзину ИА, номер карты/купона и id акции
    if ( $cart && @actionIdToBind ) {
        $self->bind_cart_card( $cart, $cardNumber, \@actionIdToBind );
    }

    my $res = $self->{ req }->new_response( 200 );
    $res->body( encode_json( \@answer ) );
    return $res->finalize();
}
################################################################################
#Подставляет в actions.action_body значения из card_action.placeholders и предопределенные из базы.
# формирует итоговый json с акцией 
sub prepareAction {
    my $self        = shift;
    my $cardNumber  = shift;
    my $card_action = shift;

    my $action_body = $card_action->{ action_body };
    my $placeholders = decode_json($card_action->{ placeholders }|| '{}');

    $placeholders->{CARD_NUMBER}   = $cardNumber;
    $placeholders->{COUPON_NUMBER} = $cardNumber;
    $placeholders->{ACTION_ID}     = $card_action->{action_id};
    $placeholders->{START_DATE}    = $card_action->{start_date};
    $placeholders->{END_DATE}      = $card_action->{end_date};

    $action_body =~ s/%%%(\w+)%%%/$placeholders->{$1}/ge;
    
    my $action = decode_json( $action_body );

    if ( $action->{ aId } && $action->{ aId } =~ /^[0-9]+$/ )
    {
        $action->{ aId } .= "_" . $cardNumber;
    }
    
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

sub couponStatus {
    my $self = shift;
    my $arg  = shift;

    my $disc_count_limit = $arg->{ limit };
    my $disc_count       = $arg->{ disc_count };

    # invalid - купон был использован и погашен ранее
    if (
        $disc_count_limit
        && $disc_count_limit <= $disc_count
        )
    {
        return (
            STATUS_INVALID,
            "disc_count_limit[$disc_count_limit] <= disc_count[$disc_count]"
        );
    }

    my $end_date = $arg->{ end_date };
    my $now_date = $arg->{ now_date };

    # купон принадлежит завершившейся промоакции
    # Даты передаются в формате "2025-03-18 23:59:59"
    # Их корректно сравнивать как строки
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

    # Акция ещё не началась
    # Даты передаются в формате "2025-03-18 23:59:59"
    # Их корректно сравнивать как строки
    if ( $now_date lt $start_date ) {
        return (
            STATUS_FAIL,
            "now_date[$now_date] < start_date[$start_date]"
        );
    }

    # fail    - не соблюдены условия промоакции
    unless ( $self->check_addr( $arg->{ addr } ) ) {
        return (
            STATUS_FAIL,
            "check_addr() - false"
        );
    }

    # ok      - Можно применять
    return (
        STATUS_OK,
        "ok"
    );
}
################################################################################
sub bind_cart_card
{
    my $self        = shift;
    my $cart        = shift;
    my $cardNumber  = shift;
    my $actionIdArr = shift;

    my $dbh = $self->{ dbh };

    my $sql = "INSERT INTO ia_cart_card
                   (cart, card_number, action_id)
                   VALUES ";
    $sql .= '(?,?,?),' x @$actionIdArr;
    chop $sql;

    my @values = map { $cart, $cardNumber, $_ } @$actionIdArr;
    $dbh->do( $sql, undef, @values )
        or die "Can't update mysql: " . $dbh->err . " (" . $dbh->errstr . ")";
}
################################################################################
sub put
{
    my $self = shift;
    my $dbh  = $self->{ dbh };

    # В транзакции делать попытку внести uniqKey в отдельную таблицу.
    # Если получилось, то обновлять акции
    # $data->{uniqKey}
    #    my $params = $arg->{req}->parameters;
    my $params = $self->{ req }->query_parameters;
    
    my $uniq_key = $params->{uniqKey};
    my $receipt_ts = $params->{receiptTS};
    my @actionsId = $params->get_all( "actionsId" );
    
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
            undef, $uniq_key, $receipt_ts,  $action_id, $card_number, $self->{shop_id} // 0
            )
            or die "Can't update mysql: " . $dbh->err . " (" . $dbh->errstr . ")";
    }

    my $res = $self->{ req }->new_response( 200 );
    $res->body( "OK\n" );
    return $res->finalize();
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
