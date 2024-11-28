use 5.14.0;
use strict;
use warnings;
use utf8;

my $dir;

BEGIN
{
    $dir = $0;
    $dir =~ s{/psgi/[^/]+$}{};
}
use lib "$dir/lib", "$dir/conf", "$dir/lib/perl";

use Plack::Builder;
use Plack::Request;

use DBI;
use Carp;
use JSON::XS;
use SFE::Logger::Stderr2;
use Const;

my $CFG = require "unit-app.conf";

SFE::Logger::Stderr2->level( $CFG->{ log_level } // 'debug' );

my $app = sub {
    my $env = shift;

    my $request = Plack::Request->new( $env );

    my $method = $request->method();
    if (
        $method eq "POST" &&
        $request->path_info() =~ m{/coupon-hold}
        )
    {
        my $answer = holdout( $request );

        my $code = exists $answer->{ error } ? 400 : 200;

        my $res = $request->new_response( $code );
        $res->headers( [ 'Content-Type' => 'application/json' ] );
        $res->body( encode_json( $answer ) );

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
    my ( $request ) = @_;

    my $params = decode_json( $request->content );

    my $dbh = connect_db();

    my $loyaltyCard = $params->{ loyaltyCard };
    my $coupon      = $params->{ coupon };
    my $cart        = $params->{ cartId };

    my $answer = {
        "cartId"      => $cart,
        "coupon"      => $coupon,
        "loyaltyCard" => $loyaltyCard,
        "status"      => STATUS_INVALID
    };
    
    my $cardNumber = $loyaltyCard;

    ($cardNumber // defined $coupon ) && $cart
        or return
        { "error" => "cartId - обязательно. Одно из полей coupon или loyaltyCard - обязательно" };
        
    $cardNumber //= 0;
    $coupon //= 0;
    
    my $usages = $dbh->selectall_arrayref( "
        SELECT us.id as usage_id,
                us.coupon_id,
                us.status,
                a.limit,
                a.type,
                NOW() AS now_date,
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
                ) AS usage_cnt_card

        FROM coupon_usage us
        JOIN coupon     c ON c.id = coupon_id
        JOIN actions_v2 a ON a.id = c.action_id 
        WHERE uniq_key = ?",
          { Slice => {} },
          $cardNumber, $cart
    );
    Errf("usages: %s ", $usages);
    scalar @$usages
        or return $answer;
    foreach my $usage (@$usages) {
        ($usage->{status} eq 'new')
            or return $answer;
            
        if (
            $usage->{type} =~ /^(?:coupon|promocode)$/ and
            $usage->{limit} and
            $usage->{limit} <= $usage->{usage_cnt}){
            return $answer;
        }
        if (
            $usage->{type} =~ /^(?:card|promocode)$/ and !$cardNumber ){
            return $answer;
        }
        if ($usage->{type} eq 'card' and 
            $usage->{limit} and $usage->{limit} <= $usage->{usage_cnt_card}){
            return $answer;
        }
        if ($usage->{type} eq 'promocode' and
                $usage->{usage_cnt_card}>0) {
            return $answer;
        }
    }

    my $qmarks = join( ',', ( "?" ) x @$usages );
    $dbh->do(
        "UPDATE `coupon_usage`
             SET status = 'holdout'
             WHERE id in ($qmarks)",
        undef, map {$_->{usage_id}} @$usages
    );


    Info("$cardNumber applied for cart $cart");
    $answer->{ status } = STATUS_OK;
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
