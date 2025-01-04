CREATE TABLE `coupon` (
  `id` BIGINT UNSIGNED NOT NULL PRIMARY KEY AUTO_INCREMENT COMMENT 'ID купона',
  `code` varchar(20) NOT NULL DEFAULT '0' COMMENT 'Номер карты, купона или промокод',
  `action_id` int unsigned NOT NULL DEFAULT '0' COMMENT 'Номер акции',
  `start_date` datetime DEFAULT NULL COMMENT 'Время старта акции',
  `end_date`   datetime DEFAULT NULL COMMENT 'Время окончания акции',
  `placeholders` json DEFAULT NULL  COMMENT 'JSON c плейсхолдерами для акций в формате {"NAME": "Александра"} или NULL',
  unique KEY (`action_id`,`code`),
  KEY (`action_id`)

) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

