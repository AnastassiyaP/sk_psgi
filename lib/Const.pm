package Const;

use strict;
use warnings;

use base 'Exporter';

use constant IA_SHOP_ID => 10**6;    # интернет аптека;

use constant STATUS_OK      => 'ok';
use constant STATUS_INVALID => 'invalid';

use constant COUPON_STATUS_NEW => 'new';
use constant COUPON_STATUS_HOLDOUT => 'holdout';
use constant COUPON_STATUS_CANCELED => 'canceled';
use constant COUPON_STATUS_ACCEPTED => 'accepted';

use constant COUPON_TYPE_CARD => 'card';
use constant COUPON_TYPE_COUPON => 'coupon';
use constant COUPON_TYPE_PROMOCODE => 'promocode';


our @EXPORT = qw(
    IA_SHOP_ID
    STATUS_OK
    STATUS_INVALID
    COUPON_STATUS_NEW
    COUPON_STATUS_HOLDOUT
    COUPON_STATUS_CANCELED
    COUPON_STATUS_ACCEPTED
    
    COUPON_TYPE_CARD
    COUPON_TYPE_COUPON
    COUPON_TYPE_PROMOCODE
);


1;
