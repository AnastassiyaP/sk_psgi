use strict;
use warnings;

my $dir;

BEGIN
{
    $dir = $0;
    $dir =~ s{/[^/]+$}{};
}

use lib 'lib', "conf", "$dir/lib";

use Plack::Builder;
use Plack::Request;
use Carp;
use JSON::XS;
use MIME::Base64;

use DB;

use SmCh::Coupon::Generate qw(
    generateCouponNumber
    generateCouponImg
);

my $CFG = do "./conf/unit-app.conf";

my $SQL_actionByActionId = <<SQL;
    SELECT *
    FROM `actions_v2`
    WHERE id = ?
      AND status = 'run'
      AND type = 'coupon'
SQL

my $SQL_AddCouponAction = <<SQL;
    INSERT
    INTO `coupon` (
        action_id,
        code
    )
    VALUES (?, ?)
SQL

my $app = sub {
    my $env = shift;

    my $req = Plack::Request->new( $env );

    my $arg = { req => $req, };

    my $method = $req->method;
    if ( $method eq "GET" )
    {
        get( $arg );
    }

    #    elsif ( $method eq "PUT" ) {
    #        put($arg);
    #    }
    else
    {
        warn "Unknown method[$method]";
    }
};
################################################################################
sub get
{
    my $arg = shift;

    my $params = $arg->{ req }->query_parameters;

    my $cmd      = $params->{ cmd };
    my $actionId = $params->{ actionId };

    my $dbh = connect_db( $CFG );

    my $result = $dbh->selectrow_hashref( $SQL_actionByActionId, undef, $actionId );

    my $answer = {};
    if ( $result )
    {
        if ( 'bmp' eq $cmd )
        {
            $answer->{ type } = 'bmp';
            $answer->{ value } =
                encode_base64( $result->{ bmp_fld } );
        }
        elsif ( 'genbmp' eq $cmd )
        {
            my $couponNumber = 99 . generateCouponNumber( 12 );
            my $couponBmp    = generateCouponImg( $result->{ bmp_fld }, $couponNumber );

            $dbh->do(
                $SQL_AddCouponAction,
                undef, $actionId, $couponNumber
            );

            $answer->{ type }  = 'bmp';
            $answer->{ value } = encode_base64( $couponBmp );
        }
        else
        {
            warn "Unknown cmd[$cmd]";
        }
    }

    $dbh->disconnect();

    my $res = $arg->{ req }->new_response( 200 );
    $res->body( encode_json( $answer ) );
    return $res->finalize();
}
################################################################################
builder
{
    enable 'ContentLength';
    $app;
};
################################################################################
