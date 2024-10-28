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
  `id` INT unsigned NOT NULL PRIMARY KEY COMMENT 'ID купона',
  `code` varchar(256)  NOT NULL COMMENT 'Номер купона или промокод',
  `action_id` int unsigned NOT NULL DEFAULT '0' COMMENT 'Номер акции',
  KEY (`action_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE `card_action` (
  `card_number` BIGINT UNSIGNED NOT NULL DEFAULT '0' COMMENT 'Номер карты',
  `action_id` int unsigned NOT NULL DEFAULT '0' COMMENT 'Номер акции',
  `placeholders` text DEFAULT NULL  COMMENT 'JSON c плейсхолдерами для акций в формате {"NAME": "Александра"} или пустая строка',
  unique KEY (`card_number`,`action_id`),
  KEY (`action_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;


CREATE TABLE `coupon_usage` (
  `coupon_id`   int unsigned NOT NULL DEFAULT '0' COMMENT 'Номер купона',
  `card_number` int unsigned NOT NULL DEFAULT '0' COMMENT 'Номер карты',
  `action_id`   int unsigned NOT NULL DEFAULT '0' COMMENT 'Номер акции',
  `uniq_key`    varchar(256) NOT NULL COMMENT 'уникальный id запроса',
  `shop_id`     int unsigned NOT NULL DEFAULT '0' COMMENT 'id магазина',
  `receipt_ts`  timestamp NOT NULL COMMENT 'время события на кассе',
  `timestamp`   timestamp DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  `status`      enum ('expired', 'holdout', 'finished' ),
  PRIMARY KEY (`card_number`,`coupon_id`, action_id, `uniq_key`),
  KEY (`shop_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;


CREATE TABLE `ia_cart_card` (
  `id`          INT UNSIGNED    NOT NULL AUTO_INCREMENT,
  `cart`        CHAR(15)        NOT NULL DEFAULT '' COMMENT 'Номер корзины',
  `coupon_id`   INT UNSIGNED NOT NULL DEFAULT '0' COMMENT 'Номер карты или купона',
  `action_id`   int unsigned NOT NULL DEFAULT '0' COMMENT 'Номер акции',
  `card_number` BIGINT UNSIGNED NOT NULL DEFAULT '0' COMMENT 'Номер карты или купона',
  `timestamp`   TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT 'Время записи',
  PRIMARY KEY (`id`),
  KEY `cart_card_number` (`cart`, `card_number`),
  KEY `card_number` (`card_number`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;


-- Акция по Купону
insert into actions_v2
         (id,status,type,   start_date,  end_date,   `limit`,action_body,options,addr,bmp_fld)
  values (1,'run',  'coupon','2024-01-01','2030-01-01',5,'{}',NULL,'{}','asdf');
insert into coupon (id, code, action_id) values (1,12313,1);
insert into coupon (id, code, action_id) values (2,41353,1);
insert into coupon (id, code, action_id) values (3,45251,1);

insert into ia_cart_card (id,coupon_id,action_id, card_number,cart) values (1,1,1, 5464,'cart45424');

insert into coupon_usage (coupon_id,card_number,action_id,uniq_key,shop_id,receipt_ts,status) values (1,5464,1,'receipt1',1,'2024-10-10','holdout');
insert into coupon_usage (coupon_id,card_number,action_id,uniq_key,shop_id,receipt_ts,status) values (2,5464,1,'receipt1',1,'2024-10-10','finished');
insert into coupon_usage (coupon_id,card_number,action_id,uniq_key,shop_id,receipt_ts,status) values (1,0,1,'receipt2',1,'2024-10-10','finished');



-----------------------------
-- Акция по промокоду
insert into actions_v2
         (id,status,type,   start_date,  end_date,   `limit`,action_body,options,addr,bmp_fld)
  values (2,'run',  'promocode','2024-01-01','2030-01-01',5,'{}',NULL,'{}','asdf');
insert into coupon (id,code,action_id) values (4,'vmeste2024',2);


insert into ia_cart_card (id,coupon_id, action_id, card_number,cart) values (2,4,2, 1234,'cart1232');
insert into coupon_usage (coupon_id, action_id, card_number,uniq_key,shop_id,receipt_ts,status)
  values (2,2, 1234,'receipt1432',1,'2024-10-10','holdout');


-- Акция по карте

insert into actions_v2
         (id,status, type,   start_date,  end_date,   `limit`,action_body,options,addr,bmp_fld)
  values (3,'run', 'card','2024-01-01','2030-01-01',5,'{}',NULL,'{}','asdf');
insert into card_action (card_number, action_id, placeholders) values (5464, 3, '{}');
insert into card_action (card_number, action_id, placeholders) values (5465, 3, '{}');
insert into card_action (card_number, action_id, placeholders) values (5466, 3, '{}');


insert into ia_cart_card (id,coupon_id,card_number, action_id, cart) values (3,0,5464, 3, 'cart3');
insert into coupon_usage (coupon_id, card_number, action_id, uniq_key, shop_id, receipt_ts, status) values (0,5464, 3, 'receipt11432', 1, '2024-10-10', 'holdout');
insert into coupon_usage (coupon_id, card_number, action_id, uniq_key, shop_id, receipt_ts, status) values (0,5464, 3, 'receipt1143', 1, '2024-10-10', 'holdout');

