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
use MIME::Base64;
use SmCh::Coupon::Generate qw(
    generateCouponNumber
    generateCouponImg
);


my $CFG = require "$dir/unit-app.conf";

#      AND start_date <= NOW()
#      AND NOW() < end_date
my $SQL_actionByActionId = <<SQL;
    SELECT *
    FROM `actions`
    WHERE parent_id = ?
      AND status = 'run'
SQL

my $SQL_AddCouponAction = <<SQL;
    INSERT
    INTO `card_action` (
        action_id,
        card_number,
        action
    )
    VALUES (?, ?, ?)
SQL

my $SQL_SetRunStatus = <<SQL;
UPDATE actions
SET status = 'run'
WHERE parent_id = ?;
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

    #my $params = $arg->{req}->parameters;
    my $params = $arg->{ req }->query_parameters;

    my $cmd      = $params->{ cmd };
    my $actionId = $params->{ actionId };

    my $dbh    = _connect_db();
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
            my $actionJson     = encode_json ( {"CARD_NUMBER": $couponNumber} );
            
            $dbh->do(
                $SQL_AddCouponAction,
                undef, $actionId, $couponNumber,
                $actionJson
            );

            # Нужно включить акцию
            # В большинстве случаев акция уже включена раньше
            $dbh->do(
                $SQL_SetRunStatus,
                undef, $actionId
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
sub _connect_db
{
    my $dbh = DBI->connect(
        $CFG->{ sql_dsn }, $CFG->{ sql_user }, $CFG->{ sql_pass },
        {
            PrintError        => 0,
            RaiseError        => 1,
            mysql_enable_utf8 => 1,
        },
        )
        or die "Can't connect to MySQL: $DBI::err ($DBI::errstr)";
    return $dbh;
}
################################################################################
