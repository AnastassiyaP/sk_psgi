CREATE TABLE `ia_cart_card` (
  `id`          INT UNSIGNED    NOT NULL AUTO_INCREMENT,
  `cart`        CHAR(15)        NOT NULL DEFAULT '',
  `card_number` BIGINT UNSIGNED NOT NULL DEFAULT '0',
  `action_id`   INT UNSIGNED    NOT NULL,
  `timestamp`   TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `cart_card_number` (`cart`,`card_number`),
  KEY `card_number` (`card_number`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
