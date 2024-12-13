#!/usr/bin/perl

use strict;
use warnings;

use lib 'conf', 'lib', 'lib/perl';

use SFE::Logger::Stderr2;
use DB;

my $CFG = require "unit-app.conf";

SFE::Logger::Stderr2->level( $CFG->{ log_level } // 'info' );

my $dbh = connect_db($CFG);
my $hours = $CFG->{hours_holdout_expired} // 72;

my $rows = $dbh->do("
    UPDATE coupon_usage
    SET status='canceled'
    WHERE status ='holdout'
      AND timestamp < date_add(
        NOW(), INTERVAL -$hours HOUR)");

if ($rows eq '0E0'){
    $rows = 0;
}

Info("Number of canceled coupons: $rows");