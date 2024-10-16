use 5.10.0;
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

my $CFG = require "$dir/unit-app.conf";

SFE::Logger->level( $CFG->{ log_level } // 'warning' );

my $SQL_actionByCardNumber = <<SQL;
   SELECT `card_action`.id, `card_action`.action_id, action, `card_action_addr`.addr
   FROM `card_action`
   LEFT JOIN `action_status` ON (`card_action`.action_id = `action_status`.action_id)
   LEFT JOIN `card_action_addr` ON (`card_action`.action_id = `card_action_addr`.action_id)
   WHERE card_number = ?
     AND `action_status`.status = 'run'
     AND start_date <= NOW()
     AND NOW() < end_date
     AND ( disc_count_limit = 0 OR disc_count < disc_count_limit ) 
SQL
my $SQL_actionByCoupon = <<SQL;
   SELECT `card_action`.id,
          `card_action`.action_id,
          action,
          `card_action_addr`.addr,
          disc_count_limit,
          disc_count,
          start_date,
          NOW() AS now_date,
          end_date,
          `action_status`.status
   FROM `card_action`
   LEFT JOIN `action_status` ON (`card_action`.action_id = `action_status`.action_id)
   LEFT JOIN `card_action_addr` ON (`card_action`.action_id = `card_action_addr`.action_id)
   WHERE card_number = ?
SQL

my $SQL_increaseCntByActionAndCardNumber = <<SQL;
   UPDATE `card_action`
   SET disc_count = disc_count + 1
   WHERE card_number = ?
     AND action_id = ?
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

    my $trade = $params->{ trade };
    if ( $trade && ( $trade eq 'undef' || $trade eq 'IA' ) ) {
        $trade = undef;
    }
    $self->{ trade } = $trade;

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
        my $action = $self->prepareAction( $cardNumber, $res->{ action } );
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
            my $action = $self->prepareAction( $cardNumber, $res->{ action } );
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
sub prepareAction {
    my $self       = shift;
    my $cardNumber = shift;
    my $actionJson = shift;

    my $action = decode_json( $actionJson );
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

    my $disc_count_limit = $arg->{ disc_count_limit };
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

    my @actionsId = $params->get_all( "actionsId" );

    foreach ( @actionsId )
    {
        my ( $action_id, $card_number ) = split "_";
        $dbh->do(
            $SQL_increaseCntByActionAndCardNumber,
            undef, $card_number, $action_id
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

    my $trade = $self->{ trade };

    # Если $trade или $addrJson не задан, то не ограничиваем по адресу
    defined $trade    or return 1;
    defined $addrJson or return 1;

    my $addr = decode_json( $addrJson );

    # Если все, то дальше смотреть не нужно
    $addr->{ all } && return 1;

    # В $addr только номера
    $trade =~ s/^TM//i;

    return checkShopIdsByAddr( $self->{ dbh }, $trade, $addr );
}
################################################################################
sub connect_db
{
    state $dbh;
    $dbh //= DBI->connect_cached(
        $CFG->{ sql_dsn }, $CFG->{ sql_user }, $CFG->{ sql_pass },
        { PrintError => 0, mysql_enable_utf8 => 1 }
        )
        or die "Can't connect to MySQL: $DBI::err ($DBI::errstr)";
    return $dbh;
}
################################################################################
