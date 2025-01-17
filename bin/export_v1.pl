#!/usr/bin/perl

use strict;
use warnings;

use lib 'conf', 'lib', 'lib/perl';

use SFE::Logger::Stderr2;
use SmCh::DB qw(connect_db);

my $CFG = require "unit-app.conf";

SFE::Logger::Stderr2->level( $CFG->{ log_level } // 'info' );

my $dbh = connect_db( $CFG );

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
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

");

$dbh->do("
CREATE TABLE `coupon` (
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
CREATE TABLE IF NOT EXISTS `coupon_usage` (
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

my %type_map = (
    "card"=>'card',
    'cp'=>'coupon'
);

while(my ($search_str, $type) = each(%type_map)) {

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
    SELECT
        a.id,
        '$type',
        a.options as action_body,
        '{}' as options,
        bmp_fld,
        ca.start_date,
        ca.end_date,
        ca.disc_count_limit,
        ifnull(s.status, 'draft'),
        ad.addr
    FROM actions a
        LEFT JOIN (
            select
                action_id,
                min(start_date) as start_date,
                min(end_date) as end_date,
                min(disc_count_limit) as disc_count_limit
            FROM card_action
            GROUP BY action_id
        ) ca on ca.action_id = a.id
        LEFT JOIN action_status s ON (a.id = s.action_id)
       LEFT JOIN card_action_addr ad ON (a.id = ad.action_id)
    WHERE options->\"\$.cnt.*[0]\" LIKE \"%$search_str.%\"
  " );
}


#что делать с сard_action.action плейсхолдерами - конвертировать ли, и как
$dbh->do( "
    INSERT INTO coupon (
        id,
        code,
        action_id
        -- placeholders
    )
    SELECT
        id,
        card_number,
        action_id
        -- action
    FROM card_action " );

my $sth_card_action = $dbh->prepare ( "
    SELECT * FROM card_action where disc_count > 0  ");

$sth_card_action->execute();
while (my $card_action = $sth_card_action->fetchrow_hashref) {
    my $usages = $card_action->{disc_count};
    my @rands = map { int(rand(10) * 10**15) } 1..$usages;
    my $sth = $dbh->prepare(
        "INSERT INTO coupon_usage (
            coupon_id,
            card_number,
            uniq_key,
            shop_id,
            status
        ) VALUES(?, ?, ?, ?, ?)");
    $sth->bind_param_array(1, $card_action->{id});
    $sth->bind_param_array(2, 0);
    $sth->bind_param_array(3, [@rands]);
    $sth->bind_param_array(4, 0);
    $sth->bind_param_array(5, "accepted"); # scalar will be reused for each row
    $sth->execute_array(
      { ArrayTupleStatus => \my @tuple_status } );
        
}

