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

use Carp;
use JSON::XS;
use SFE::Logger::Stderr2;

use SmCh::DB qw(connect_db);
use SmCh::Const;

my $CFG = do "./conf/unit-app.conf";

SFE::Logger::Stderr2->level( $CFG->{ log_level } // 'debug' );

my $app = sub {
    my $env = shift;

    my $request = Plack::Request->new( $env );

    my $method    = $request->method();
    my $path_info = $request->path_info();
    my $res;
    if ( $method eq "POST" ) {
        my $answer = $path_info =~ m{/coupon-hold$}
            ? holdout( $request )
            : $path_info =~ m{/coupon-unhold$}
            ? unhold( $request )
            : undef;

        unless ( defined $answer ) {
            Warning( "Unknown path_info[$path_info]" );
            return not_found( $request );
        }
        my $code = exists $answer->{ error } ? 400 : 200;

        $res = $request->new_response( $code );
        $res->headers( [ 'Content-Type' => 'application/json' ] );
        $res->body( encode_json( $answer ) );
        return $res->finalize();
    }
    Warning( "Unknown method[$method] path_info[$path_info]" );

    return not_found( $request );
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

    my $dbh = connect_db( $CFG );

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

    ( $cardNumber // defined $coupon ) && $cart
        or return
        { "error" => "cartId - обязательно. Одно из полей coupon или loyaltyCard - обязательно" };

    $cardNumber //= 0;
    $coupon     //= 0;

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
    @$usages
        or return $answer;

    # промокод - 2 лимита: 1 применение по карте и общий лимит на к-во карт
    # купон - Лимит применений без привязки к карте
    # карта - лимит на карту
    foreach my $usage ( @$usages ) {
        ( $usage->{ status } eq COUPON_STATUS_NEW )
            or return $answer;

        if (
            $usage->{ type } =~ /^(?:coupon|promocode)$/ and
            $usage->{ limit } and
            $usage->{ limit } <= $usage->{ usage_cnt }
            )
        {
            return $answer;
        }
        if (
            $usage->{ type } =~ /^(?:card|promocode)$/
            and !$cardNumber
            )
        {
            return $answer;
        }
        if (
            $usage->{ type } eq COUPON_TYPE_CARD
            and
            $usage->{ limit } and $usage->{ limit } <= $usage->{ usage_cnt_card }
            )
        {
            return $answer;
        }
        if ( $usage->{ type } eq COUPON_TYPE_PROMOCODE and $usage->{ usage_cnt_card } > 0 ) {
            return $answer;
        }
    }

    my $qmarks = join( ',', ( "?" ) x @$usages );
    $dbh->do(
        "UPDATE `coupon_usage`
             SET status = ?
             WHERE id in ($qmarks)",
        undef,
        COUPON_STATUS_HOLDOUT,
        map { $_->{ usage_id } } @$usages
    );

    Info( "$cardNumber applied for cart $cart" );

    $answer->{ status } = STATUS_OK;
    return $answer;
}
################################################################################
sub unhold
{
    my ( $request ) = @_;
    my $params;
    eval {
        $params = decode_json( $request->content );
    } or return { "error" => "Malformed JSON string" };
    my $dbh = connect_db( $CFG );

    my $cart        = $params->{ cartId };
    my $loyaltyCard = $params->{ loyaltyCard };
    my $coupon      = $params->{ coupon };

    my $cardNumber = $loyaltyCard;

    ( $cardNumber // defined $coupon )
        or return { "error" => "Одно из полей coupon или loyaltyCard - обязательно" };

    my $answer = {
        "cartId"      => $cart,
        "coupon"      => $coupon,
        "loyaltyCard" => $loyaltyCard,
        "status"      => STATUS_INVALID
    };

    $cardNumber //= 0;
    unless ( defined $cart ) {

        my $q = "";
        my @code  = defined $coupon ? ($coupon) : ($cardNumber);
        if( $cardNumber ) {
            push @code, $cardNumber; 
            $q = "AND card_number = ?";
        }
            
        my $carts = $dbh->selectall_arrayref( "
             SELECT uniq_key 
             FROM coupon_usage us 
             JOIN coupon     c ON c.id = coupon_id
             JOIN actions_v2 a ON a.id = c.action_id 
             WHERE code = ?
              $q
             AND us.status=?
             LIMIT 2
             ",
            { Slice => {} },
            @code,
            COUPON_STATUS_HOLDOUT
            );

        @$carts or return $answer;
        if ( @$carts > 1 ) {
            return {
                "error" => "Купон захолдирован несколько раз, не удается выбрать корзину"
            };
        }
        $cart = $carts->[ 0 ]->{ uniq_key };
    }

    my @code;
    for my $code ( $cardNumber, $coupon ) {
        if ( defined $code ) {
            push @code, $code;
        }
    }
    my $qmarks = join( ',', ( '?' ) x @code );
    my $usages = $dbh->selectall_arrayref( "
        SELECT us.id as usage_id,
                c.action_id,
                us.coupon_id,
                us.card_number,
                c.code,
                a.limit,
                a.type                
        FROM coupon_usage us
        JOIN coupon     c ON c.id = coupon_id
        JOIN actions_v2 a ON a.id = c.action_id 
        WHERE uniq_key = ?
        AND code in ($qmarks)
        AND us.status=?",
        { Slice => {} },
        $cart,
        @code,
        COUPON_STATUS_HOLDOUT
    );
    @$usages
        or return $answer;

    foreach my $usage ( @$usages ) {
        if (
            $usage->{ type } =~ /^(?:card|promocode)$/
            and !$cardNumber
            )
        {
            return $answer;
        }
        if ( $cardNumber != $usage->{ card_number } ) {
            return $answer;
        }
    }

    $qmarks = join( ',', ( "?" ) x @$usages );
    $dbh->do(
        "UPDATE `coupon_usage`
             SET status = ?
             WHERE id in ($qmarks)",
        undef,
        COUPON_STATUS_CANCELED,
        map { $_->{ usage_id } } @$usages
    );

    Infof(
        "Unholded actions %s with coupon %s, card_number %s",
        [ map { $_->{ action_id } } @$usages ],
        $coupon,
        $cardNumber
    );

    $answer->{ status } = STATUS_OK;
    return $answer;
}
################################################################################
