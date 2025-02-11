#!/usr/bin/perl

use strict;
use warnings;

use lib 'conf', 'lib', 'lib/perl';

use SFE::Logger::Stderr2;
use SmCh::DB qw(connect_db);
use Try::Tiny;
use JSON::XS;

my $CFG = require "unit-app.conf";

SFE::Logger->level( $CFG->{ log_level } // 'debug' );

my $dbh = connect_db($CFG);

$dbh->do("DROP table actions_v2");
$dbh->do("DROP table coupon");
$dbh->do("DROP table coupon_usage");

$dbh->do("
CREATE TABLE  `actions_v2` (
  `id`         int unsigned NOT NULL DEFAULT '0' COMMENT 'id акции',
  `status`     enum('run', 'stop', 'draft') NOT NULL DEFAULT 'draft',
  `type`       varchar(255) NOT NULL COMMENT 'Тип акции. coupon, card, promocode',
  `start_date` datetime DEFAULT NULL COMMENT 'Время старта акции',
  `end_date`   datetime DEFAULT NULL COMMENT 'Время окончания акции',
  `limit`      int unsigned NOT NULL DEFAULT '0' COMMENT 'Количество применений купона. 0 – Безлимитно', 
  `action_body` json DEFAULT NULL COMMENT 'Тело акции',
  `options` json DEFAULT NULL COMMENT 'Опции акции',
  `addr` json DEFAULT NULL COMMENT 'Адреса, для которых работает акция',
  `bmp_fld` blob COMMENT 'Картинка для печати',
  `update_time` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

");

$dbh->do("
CREATE TABLE  `coupon` (
  `id` BIGINT UNSIGNED NOT NULL PRIMARY KEY AUTO_INCREMENT COMMENT 'ID купона',
  `code` varchar(20) NOT NULL DEFAULT '0' COMMENT 'Номер карты, купона или промокод',
  `action_id` int unsigned NOT NULL DEFAULT '0' COMMENT 'Номер акции',
  `start_date` datetime DEFAULT NULL COMMENT 'Время старта акции',
  `end_date`   datetime DEFAULT NULL COMMENT 'Время окончания акции',
  `placeholders` json DEFAULT NULL  COMMENT 'JSON c плейсхолдерами для акций в формате {\"NAME\": \"Александра\"} или NULL',
  unique KEY (`action_id`,`code`),
  KEY (`action_id`)

) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
");
$dbh->do("
CREATE TABLE `coupon_usage` (
  `id` BIGINT unsigned NOT NULL AUTO_INCREMENT COMMENT 'ID  погашения купона',
  `coupon_id` BIGINT unsigned NOT NULL DEFAULT '0' COMMENT 'ID купона или связи карты и акции',
  `card_number` bigint unsigned NOT NULL DEFAULT '0' COMMENT 'Номер карты',
  `uniq_key` varchar(20) NOT NULL COMMENT 'уникальный id запроса - номер корзины или чека',
  `shop_id` int unsigned NOT NULL DEFAULT '0' COMMENT 'id магазина',
  `receipt_ts` timestamp NULL DEFAULT NULL COMMENT 'время события на кассе',
  `timestamp` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT 'Время записи',
  `status` enum('new','holdout','canceled','accepted') DEFAULT 'new',
  PRIMARY KEY (`id`),
  UNIQUE KEY `key_card_number` (`uniq_key`,`coupon_id`),
  KEY `card_number` (`card_number`),
  KEY `shop_id` (`shop_id`)
) ENGINE=InnoDB AUTO_INCREMENT=2061 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci
");

Info("Tables created");

my %type_map = (
    "card"=>'card',
    'cp'=>'coupon'
);
# m1
#|     11088 |
#|     12301 |
#|     12302 |
#|     12318 |
#|     12334 |
#+-----------+


#действующие акции
#|     10534 |
#|     10535 |
#|     11088 |
#|     11089 |
#|     11566 |
#|     11731 |
#|     11732 |
#|     11733 |
#|     11734 |
#|     11735 |
#|     11736 |
#|     11737 |
#|     11738 |
#|     11887 |
#|     12088 |
#|     12091 |
#|     12092 |
#|     12093 |
#|     12094 |
#|     12095 |
#|     12301 |
#|     12302 |
#|     12306 |
#|     12307 |
#|     12308 |
#|     12311 |
#|     12312 |
#|     12318 |
#|     12320 |
#|     12334 |
#|     12395 |

#TODO:
#обнулить просроченные купоны
#Придумать обратную конвертацию чтобы убедиться что других расхождений нет
# Добавить  card в card_usage 
sub save_action {
    my $card = shift;
    my $action_id = $card->{action_id};
    
    Info("Card $card->{id} in process");
    
    my $status = $dbh->selectrow_array(
        "select status
        FROM action_status
        WHERE action_id = $action_id");
    my $addr = $dbh->selectrow_array(
        "select addr
        FROM card_action_addr
        WHERE action_id = $action_id");
    my $bmp_fld = $dbh->selectrow_array(
        "select bmp_fld
        FROM actions
        WHERE parent_id = $action_id");
    
    my ($type, $action_body, $placeholders) = split_action_body(decode_json($card->{action}));
    unless (defined $type){
        warn "Unknown type for $action_id; Skip action";
        return;
    }
    if ( $card->{end_date} lt '2025-01-20 00:00:00' ){
        $action_body = {};
        #$placeholders = {};
    } else {
        save_coupons ($action_id, $placeholders);
    }
    
    Debugf("Action %s: type %s, placeholders %s",$action_id, $type, $placeholders);


    $dbh->do( "
        INSERT INTO actions_v2 (
            id,
            type,
            action_body,
            options,
            bmp_fld,
            start_date,
            end_date,
            `limit`,
            status,
            addr )
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?) ",
        undef,
        $action_id,
        $type,
        encode_json($action_body),
        '{}',
        $bmp_fld,
        $card->{start_date},
        $card->{end_date},
        $card->{disc_count_limit},
        $status,
        $addr,
    );
}

#TODO все купоны акции сохранить сформировав плейсхолдеры в mysql
sub save_coupons {
    my ($action_id, $placeholders) = @_;
    #Должны получить функцию вида: json_object("cnt_2_1",options->"$.cnt.c2[1]", "cnt_3_1",options->"$.cnt.c3[1]") 
    $placeholders = join(', ', %$placeholders);
    Info("$placeholders");
    $dbh->do( "
        INSERT INTO coupon (
            id,
            code,
            action_id,
            placeholders
        ) SELECT
        id,
        card_number,
        $action_id,
        JSON_OBJECT($placeholders)
        from card_action
        WHERE action_id = $action_id"
    );
}

sub split_action_body {
    my $action = shift;
    Debugf("action body: %s", $action);
    my $placeholders = {};
    my $type;

    foreach my $i (2..10) {
        last unless exists $action->{"cnt"}->{"c$i"};
        if( $action->{"cnt"}{"c$i"}[0] =~ '^cp\.*'){
            $type = "coupon";
        } elsif( $action->{"cnt"}{"c$i"}[0] =~ '^card\.*'){
            $type = "card";
        }else {
            next;
        }
            
        my $len = @{$action->{"cnt"}->{"c$i"}};
        foreach my $j (1..$len - 1 ) {
            my $pl_name = "cnt_$i\_$j";
            #$placeholders->{$pl_name} = $action->{"cnt"}{"c$i"}[$j];
            $placeholders->{"'$pl_name'"} = "action->\"\$.cnt.c$i\[$j\]\"";
            $action->{"cnt"}{"c$i"}[$j] = "%%%$pl_name%%%";
        }
    }
    return $type, $action, $placeholders;
}

my $sth_action_id = $dbh->prepare (
    "SELECT distinct action_id
    FROM card_action
    WHERE action_id NOT IN (
        SELECT id FROM actions_v2)");

$sth_action_id->execute();
while (my $action_id = $sth_action_id->fetchrow_array) {
    Info("action $action_id in process"); 

    #my $sth_card_action = $dbh->prepare (
    my $first_card = $dbh->selectrow_hashref(
        "SELECT *
        FROM card_action ca
        WHERE action_id = $action_id
        limit 1"
    );

    $dbh->{AutoCommit} = 0;
    try {
        save_action($first_card);
        $dbh->commit;   # commit the changes if we get this far
    } catch {
        warn "Transaction aborted because $_"; # Try::Tiny copies $@ into $_
        eval { $dbh->rollback };
    };
}

my $sth_card_action = $dbh->prepare ( "
    SELECT ca.id, card_number, disc_count,ca.start_date, a.type FROM card_action ca
    JOIN actions_v2 a on a.id = ca.action_id 
    WHERE disc_count > 0  ");
Info("coupon usage");
$sth_card_action->execute();

my (@id, @card_number, @timestamp);
my $query = 
    "INSERT INTO coupon_usage (
        coupon_id,
        card_number,
        timestamp,
        uniq_key,
        shop_id,
        status
    ) VALUES(
        ?,
        ?,
        ?,
        FLOOR(RAND()* pow(10,12)),
        0,
        'accepted')";
my $sth = $dbh->prepare($query);

while (my $card_action = $sth_card_action->fetchrow_hashref) {
    my $usages = $card_action->{disc_count};
    my $card_number = $card_action->{type} eq 'card'
        ? $card_action->{card_number}
        : 0;


    push @id, ($card_action->{id}) x $usages;
    push @card_number, ($card_number) x $usages;
    push @timestamp, ($card_action->{start_date}) x $usages;

    
    if (@id >= 1000){
        my $rows = $sth->execute_array(
            { ArrayTupleStatus => \my @tuple_status },
            \@id,
            \@card_number,
            \@timestamp
        );

        if ($rows) {
	    Info("Inserted $rows rows");
	} else {
            Errf("failed to insert %s", \@tuple_status);
            last;
        }
        $dbh->commit;
        
        @id = ();
        @card_number = ();
        @timestamp = ();
        my $sth = $dbh->prepare($query);
    }
}
Info("Finish");
#
#
#
#sub insert{
#"
#INSERT INTO coupon_usage (
#    coupon_id,
#    card_number,
#    uniq_key,
#    shop_id,
#    status,
#    timestamp
#)
#    SELECT
#    ca.id,
#    CASE WHEN a.type='card' then card_number else 0 end,
#    FLOOR(RAND()* pow(10,12)),
#    0,
#    'accepted',
#    ca.start_date
#    FROM card_action ca
#    JOIN actions_v2 a on a.id = ca.action_id 
#    WHERE disc_count > 0
#}

