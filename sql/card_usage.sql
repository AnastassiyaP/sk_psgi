CREATE TABLE `card_usage` (
  `id`          int unsigned NOT NULL AUTO_INCREMENT,
  `card_number` int unsigned NOT NULL DEFAULT '0',
  `action_id`   int unsigned NOT NULL DEFAULT '0',
  `shop_id`     int unsigned NOT NULL DEFAULT '0',
  `timestamp`   timestamp DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY (`card_number`, `action_id`),
  KEY (`shop_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;