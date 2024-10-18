CREATE TABLE `card_action` (
  `card_number` bigint unsigned NOT NULL DEFAULT '0' COMMENT 'Номер карты или купона',
  `action_id` int unsigned NOT NULL DEFAULT '0' COMMENT 'id акции из actions_v2',
  `placeholders` text NOT NULL  COMMENT 'JSON c плейсхолдерами для акций в формате {"NAME": "Александра"} или пустая строка',
  PRIMARY KEY (`card_number`,`action_id`),
  KEY (`action_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;