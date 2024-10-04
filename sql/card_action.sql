CREATE TABLE `card_action` (
  `card_number` bigint unsigned NOT NULL DEFAULT '0',
  `action_id` int unsigned NOT NULL DEFAULT '0',
  `placeholders` text NOT NULL,
  PRIMARY KEY (`card_number`,`action_id`),
  KEY (`action_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;