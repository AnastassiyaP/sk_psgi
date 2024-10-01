CREATE TABLE `card_action_addr` (
  `action_id` int unsigned NOT NULL,
  `addr` json DEFAULT NULL,
  PRIMARY KEY (`action_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='Привязка ПП акций к аптекам, Макробрендам и тд.';
