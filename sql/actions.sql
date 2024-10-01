CREATE TABLE `actions` (
  `id` varchar(64) NOT NULL DEFAULT '0',
  `parent_id` int unsigned NOT NULL,
  `type` varchar(128) NOT NULL,
  `options` json NOT NULL,
  `bmp_fld` blob,
  `start_date` datetime DEFAULT NULL,
  `end_date` datetime DEFAULT NULL,
  `status` enum('run','stop','draft') DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index2` (`parent_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
