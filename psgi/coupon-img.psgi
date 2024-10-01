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
        start_date,
        end_date,
        action,
        disc_count_limit,
        disc_count
    )
    VALUES (?, ?, ?, ?, ?, ?, ?)
SQL

my $SQL_SetRunStatus = <<SQL;
    INSERT IGNORE
    INTO `action_status` (
        action_id,
        status
    )
    VALUES (?, 'run')
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
            my $coupon       = $couponNumber;
            my $couponBmp    = generateCouponImg( $result->{ bmp_fld }, $coupon );

            my $action = decode_json( $result->{ options } );
            $action->{ aId } = $actionId;

            my $cntCpCode = getFreeCntInAction( $action );
            $action->{ cnt }->{ $cntCpCode } = [ "cp.code", $coupon ];

            foreach ( @{ $action->{ rls } } )
            {
                $_->{ cond } = "$cntCpCode>0 & (" . $_->{ cond } . ")";
            }

            my $discCountLimit = 1;
            my $discCount      = 0;
            my $actionJson     = encode_json( $action );

            $dbh->do(
                $SQL_AddCouponAction,
                undef, $actionId, $couponNumber, $result->{ start_date },
                $result->{ end_date }, $actionJson, $discCountLimit, $discCount
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
# Ищем первый свободный счётчик
sub getFreeCntInAction
{
    my $action = shift;
    my $cntCpCode;
    for ( my $i = 1 ; $i <= 100 ; ++$i )
    {
        $cntCpCode = "c$i";
        unless ( $action->{ cnt }->{ $cntCpCode } )
        {
            last;
        }
    }
    return $cntCpCode;
}
################################################################################
