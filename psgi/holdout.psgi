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
use Const qw(IA_SHOP_ID STATUS_OK STATUS_INVALID);

my $CFG = require "$dir/unit-app.conf";

SFE::Logger::Stderr2->level( $CFG->{ log_level } // 'debug' );


my $app = sub {
    my $env = shift;

    my $request = Plack::Request->new( $env );

    my $method = $request->method();
    if ( $method eq "POST" &&
        $request->path_info() =~ m{/coupon-hold} )
    {
        my $answer= holdout($request);
            
        my $res = $request->new_response( 200 );
        $res->headers([ 'Content-Type' => 'application/json' ]);
        $res->body( encode_json($answer) );
        return $res->finalize();
    }

    Warning( "Unknown method[$method]" );

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
    my ($request) = @_;
    # TODO:
    # проверка карты по акции, а не купона
    # проверка что купон можно применить
    # проверка корзины в ia_cart_card
    # что делать с receiptTS и uniqKey
    #
    
    my $params =  decode_json($request->content);
    
    my $dbh = connect_db();

    #my $cardNumber = $params->{ cardNumber };
    my $coupon = $params->{ coupon };
    my $cart   = $params->{ cartId };
    
    my $answer = { "cartId" => $cart,
                   "coupon" => $coupon,
                   "status" => STATUS_INVALID
                };
    $coupon && $cart
        or return $answer;
        
    my $action_ids = $dbh->selectcol_arrayref( "
            SELECT action_id
            FROM ia_cart_card
            WHERE cart = ?
              AND card_number = ?
              AND timestamp = (
                 SELECT max(timestamp)
                 FROM ia_cart_card
                 WHERE cart = ?
                   AND card_number = ?)",
            {Columns => [1]},
            $cart, $coupon, $cart, $coupon )
        or return $answer;

    
    my $qmarks = join(',',("?") x @$action_ids);
    my $valid_acts = $dbh->selectcol_arrayref( "
        SELECT card_action.action_id
        FROM card_action
        JOIN action_status ON card_action.action_id=action_status.action_id
        WHERE card_number = ?
          AND card_action.action_id in($qmarks)
          AND action_status.status = 'run'
          AND start_date <= NOW()
          AND NOW() < end_date
          AND ( disc_count < disc_count_limit
             OR disc_count_limit = 0)
          ",
         undef,
         ($coupon, @$action_ids)
    );
    
    my $valid_act_cnt = scalar @$valid_acts;
    Infof( "cart action cnt: %s, ids: %s, valid acts cnt: %s, ids: %s",
          scalar @$action_ids,
          $action_ids,
          scalar @$valid_acts,
          $valid_acts);
    (scalar @$valid_acts == scalar @$action_ids)
        or return $answer;

    $dbh->do(
        "UPDATE `card_action`
             SET disc_count = disc_count + 1
             WHERE card_number = ?
               AND action_id in ($qmarks)",
        undef, $coupon, @$action_ids
    );
    
    $answer->{status} = STATUS_OK;
    return $answer;
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
