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

use constant IA_SHOP_ID => 10 ** 6; # интернет аптека;
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
                   "status" => "invalid" };
    $coupon && $cart
        or return $answer;
        
    my $action_ids = $dbh->selectcol_arrayref( "SELECT action_id
                   FROM ia_cart_card
                   WHERE
                           cart = ?
                       AND card_number = ?
                       AND timestamp = (select max(timestamp) from ia_cart_card where cart=? and card_number=?)",
                       {Columns=>[1]},
                       $cart, $coupon, $cart, $coupon )
        or return $answer;

    
    my $qmarks = join(',',("?") x scalar @$action_ids);
    my $act_cnt = $dbh->selectrow_array( "select COUNT(*) from `card_action`
                                        join action_status on card_action.action_id=action_status.action_id
         where (disc_count < disc_count_limit  or disc_count_limit = 0)
         AND `action_status`.status = 'run'
         AND start_date <= NOW()
         AND NOW() < end_date
         AND card_number = ?
         AND card_action.action_id in($qmarks)",
         undef,
         ($coupon, @$action_ids)
    );
    
    Debugf( "cart action ids: %s, valid acts cnt: %s", $action_ids, $act_cnt);
    ($act_cnt == scalar @$action_ids)
        or return $answer;

    $dbh->do(
        "UPDATE `card_action`
             SET disc_count = disc_count + 1
             WHERE card_number = ?
               AND action_id in ($qmarks)",
        undef, $coupon, @$action_ids
    );
    
    $answer->{status} = 'ok';
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
