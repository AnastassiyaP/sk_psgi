package Const;

use strict;
use warnings;

use base 'Exporter';
our @EXPORT_OK = qw(IA_SHOP_ID STATUS_OK STATUS_INVALID);

use constant IA_SHOP_ID => 10**6;    # интернет аптека;

use constant STATUS_OK      => 'ok';
use constant STATUS_INVALID => 'invalid';

1;
