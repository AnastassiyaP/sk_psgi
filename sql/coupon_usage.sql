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


