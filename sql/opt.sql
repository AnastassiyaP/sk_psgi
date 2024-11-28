--TODO
--receipt_ts – для ИА – null?
--type в actions – какие бывают и что значат?
-- синхронизация корзины вместо затирания
-- вернуть информацию об

CREATE TABLE `actions_v2` (
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


CREATE TABLE `coupon` (
  `id` INT UNSIGNED NOT NULL PRIMARY KEY AUTO_INCREMENT COMMENT 'ID купона',
  `code` varchar(256) NOT NULL DEFAULT '0' COMMENT 'Номер карты, купона или промокод',
  `action_id` int unsigned NOT NULL DEFAULT '0' COMMENT 'Номер акции',
  `start_date` datetime DEFAULT NULL COMMENT 'Время старта акции',
  `end_date`   datetime DEFAULT NULL COMMENT 'Время окончания акции',
  `placeholders` json DEFAULT NULL  COMMENT 'JSON c плейсхолдерами для акций в формате {"NAME": "Александра"} или пустая строка',
  unique KEY (`code`, `action_id`),
  KEY (`action_id`)

) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;


CREATE TABLE `coupon_usage` (
  `id`          INT UNSIGNED NOT NULL PRIMARY KEY AUTO_INCREMENT COMMENT 'ID  погашения купона',
  `coupon_id`   INT UNSIGNED    NOT NULL DEFAULT '0' COMMENT 'ID купона или связи карты и акции',
  `card_number` BIGINT UNSIGNED NOT NULL DEFAULT '0' COMMENT 'Номер карты',
  `uniq_key`    varchar(256)    NOT NULL COMMENT 'уникальный id запроса - номер корзины или чека',
  `shop_id`     int unsigned    NOT NULL DEFAULT '0' COMMENT 'id магазина',
  `receipt_ts`  timestamp       DEFAULT NULL COMMENT 'время события на кассе',
  `timestamp`   TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT 'Время записи',
  `status`      enum ('new', 'holdout', 'canceled', 'accepted' ) DEFAULT 'new',
  UNIQUE KEY `key_card_number` (`uniq_key`, `card_number`, `coupon_id`),
  KEY `card_number` (`card_number`),
  KEY (`shop_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;


-- запросы
--карта по купону и корзине
select card_number from ia_cart_card where coupon_id=$coupon_id and cart=$cart;

   SELECT coupon.*
   from coupon c
   join actions_v2 a on c.action_id=a.id
   
   where c.code=$coupon
    AND a.status = 'run'
     AND a.start_date <= NOW()
     AND NOW() < a.end_date
     AND limit = 0 

-- количество использований вообще
select count(*) from coupon_usage
where coupon_id = $coupon_id
and status in('holdout', 'accepted')


-- количество использований с этой картой

select count(*) from coupon_usage
where coupon_id = $coupon_id
and status in('holdout','accepted') and card_number=$card_number


   FROM `card_action`
   JOIN `actions_v2` actions  ON (`card_action`.action_id = `actions`.id)
   WHERE card_number = ?
     AND `actions`.status = 'run'
     AND actions.start_date <= NOW()
     AND NOW() < actions.end_date
     AND ( `limit` = 0 OR (
                select count(*) from card_usage
                where card_number = card_action.card_number
                and action_id = card_action.action_id
            ) <= `limit`
         ) 