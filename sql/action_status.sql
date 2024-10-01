CREATE TABLE `action_status` (
  `id` int unsigned NOT NULL AUTO_INCREMENT,
  `action_id` int unsigned NOT NULL,
  `status` enum('run','stop','draft') NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `action_id_UNIQUE` (`action_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
