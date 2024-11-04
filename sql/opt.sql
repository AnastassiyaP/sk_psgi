CREATE TABLE `actions_v2` (
  `id`         int unsigned NOT NULL DEFAULT '0' COMMENT 'id акции',
  `status`     enum('run','stop','draft') NOT NULL DEFAULT 'draft',
  `type`       varchar(255) NOT NULL COMMENT 'Тип акции. К примеру, coupon',
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
  `id` int unsigned NOT NULL  PRIMARY KEY COMMENT 'Номер купона',
  `code` varchar(256) NOT NULL DEFAULT '0' COMMENT 'Номер карты, купона или промокод',
  `action_id` int unsigned NOT NULL DEFAULT '0' COMMENT 'Номер акции',
  `start_date` datetime DEFAULT NULL COMMENT 'Время старта акции',
  `end_date`   datetime DEFAULT NULL COMMENT 'Время окончания акции',
  `type` enum('card', 'coupon', 'promocode') COMMENT 'Ттип значения в поле code',
  `placeholders` text DEFAULT NULL  COMMENT 'JSON c плейсхолдерами для акций в формате {"NAME": "Александра"} или пустая строка',
  unique KEY (`code`, `action_id`,`type`),
  KEY (`action_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;


CREATE TABLE `coupon_usage` (
  `uniq_key`    varchar(256)    NOT NULL COMMENT 'уникальный id запроса - номер корзины или чека',
  `shop_id`     int unsigned    NOT NULL DEFAULT '0' COMMENT 'id магазина',
  `receipt_ts`  timestamp       NOT NULL COMMENT 'время события на кассе',
  `coupon_id`   INT UNSIGNED    NOT NULL DEFAULT '0' COMMENT 'Номер карты или купона',
  `card_number` BIGINT UNSIGNED NOT NULL DEFAULT '0' COMMENT 'Номер карты или купона',
  `timestamp`   TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT 'Время записи',
  `status`      enum ('new', 'holdout', 'canceled', 'accepted' ) DEFAULT 'new',
  PRIMARY KEY `key_card_number` (`uniq_key`, `card_number`, `coupon_id`),
  KEY `card_number` (`card_number`)
  KEY (`shop_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;


-- Акция по Купону
insert into actions_v2
         (id,status,type,   start_date,  end_date,   `limit`,action_body,options,addr,bmp_fld)
  values (1,'run',  'coupon','2024-01-01','2030-01-01',5,'{}',NULL,'{}','asdf');
insert into coupon (id,code,action_id,type,placeholders) values (1,'121',1,'coupon','{}');
insert into coupon (id,code,action_id,type,placeholders) values (2,'122',1,'coupon','{}');
insert into coupon (id,code,action_id,type,placeholders) values (3,'123',1,'coupon','{}');

insert into ia_cart_card (id,coupon_id,card_number,cart) values (1,1,5464,'cart45424');
insert into coupon_usage (coupon_id,card_number,uniq_key,shop_id,receipt_ts,status) values (1,5464,'receipt1',1,'2024-10-10','holdout');
insert into coupon_usage (coupon_id,card_number,uniq_key,shop_id,receipt_ts,status) values (2,5464,'receipt1',1,'2024-10-10','finished');
insert into coupon_usage (coupon_id,card_number,uniq_key,shop_id,receipt_ts,status) values (1,0,'receipt2',1,'2024-10-10','finished');


-- Акция по промокоду
insert into actions_v2
         (id,status,type,   start_date,  end_date,   `limit`,action_body,options,addr,bmp_fld)
  values (2,'run',  'promocode','2024-01-01','2030-01-01',5,'{}',NULL,'{}','asdf');
insert into coupon (id,code,action_id,type,placeholders) values (4,'vmeste2024',2,'promocode','{}');


insert into ia_cart_card (id,coupon_id,card_number,cart) values (2,4,1234,'cart1232');
insert into coupon_usage (coupon_id,card_number,uniq_key,shop_id,receipt_ts,status) values (2,1234,'receipt1432',1,'2024-10-10','holdout');


-- Акция по карте

insert into actions_v2
         (id,status, type,   start_date,  end_date,   `limit`,action_body,options,addr,bmp_fld)
  values (3,'run', 'card','2024-01-01','2030-01-01',5,'{}',NULL,'{}','asdf');
insert into coupon (id,code,action_id,type,placeholders) values (5,'5464',3,'card','{}');
insert into coupon (id,code,action_id,type,placeholders) values (6,'5465',3,'card','{}');
insert into coupon (id,code,action_id,type,placeholders) values (7,'5466',3,'card','{}');


insert into ia_cart_card (id,coupon_id,card_number,cart) values (3,5,5464,'cart3');
insert into coupon_usage (coupon_id, card_number, uniq_key, shop_id, receipt_ts, status) values (5,5464, 'receipt11432', 1, '2024-10-10', 'holdout');
insert into coupon_usage (coupon_id, card_number, uniq_key, shop_id, receipt_ts, status) values (6,5464, 'receipt11432', 1, '2024-10-10', 'holdout');


-- запросы
карта по купону и корзине
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
and status in('holdout','accepted')

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