CREATE TABLE `card_usage` (
  `uniq_key`    int unsigned NOT NULL COMMENT 'уникальный id запроса',
  `card_number` int unsigned NOT NULL DEFAULT '0',
  `action_id`   int unsigned NOT NULL DEFAULT '0',
  `shop_id`     int unsigned NOT NULL DEFAULT '0',
  `receipt_ts`  timestamp NOT NULL COMMENT 'время события на кассе',
  `timestamp`   timestamp DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`uniq_key`),
  KEY (`card_number`, `action_id`),
  KEY (`shop_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;