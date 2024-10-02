CREATE TABLE `card_action` (
  `id` int unsigned NOT NULL AUTO_INCREMENT,
  `action_id` int unsigned NOT NULL,
  `card_number` bigint unsigned NOT NULL DEFAULT '0',
  `action` json NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index3` (`card_number`,`action_id`),
  KEY `card_number` (`card_number`),
  KEY `index4` (`action_id`)
) ENGINE=InnoDB AUTO_INCREMENT=389975470 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
