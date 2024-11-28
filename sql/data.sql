
-- Акция по Купону. Даты в actions_v2, привязки к картам нет.
insert into actions_v2 (id,status,type,   start_date,  end_date,   `limit`,action_body,options,addr,bmp_fld) values (1,'run',  'coupon','2024-01-01','2030-01-01',5,'{"Купон  %%%COUPON_NUMBER%%% для карты %%%CARD_NUMBER%%% по акции %%%ACTION_ID%%% %%%START_DATE%%% %%%END_DATE%%%": "%%%COUPON_VAR%%%"}',NULL,'{}','asdf');

insert into coupon (id,code,action_id,placeholders) values (1,'121',1,'{"COUPON_VAR":  1}');
insert into coupon (id,code,action_id,placeholders) values (2,'122',1,'{"COUPON_VAR":  2}');
insert into coupon (id,code,action_id,placeholders) values (3,'123',1,'{"COUPON_VAR":  3}');

-- применения  купона № 1 в интернет аптеке
insert into coupon_usage (coupon_id,card_number,uniq_key,shop_id,receipt_ts,status)
  values (1,0,'cart1', 1000000, null,'new');
insert into coupon_usage (coupon_id,card_number,uniq_key,shop_id,receipt_ts,status)
  values (1,0,'cart2', 1000000, null,'new');
insert into coupon_usage (coupon_id,card_number,uniq_key,shop_id,receipt_ts,status)
  values (1,0,'cart3', 1000000, null,'holdout');
insert into coupon_usage (coupon_id,card_number,uniq_key,shop_id,receipt_ts,status)
  values (1,0,'cart4', 1000000, null,'accepted');

-- применения  купона № 1 в магазине
insert into coupon_usage (coupon_id,card_number,uniq_key,shop_id,receipt_ts,status)
  values (1,0,'receipt1',1,'2024-10-10','accepted');


-- Акция по промокоду. Одно применение  на карту
insert into actions_v2 (id, status,type, start_date, end_date,   `limit`,action_body,options,addr,bmp_fld)
  values (2,'run',  'promocode','2024-01-01','2030-01-01',3,'{"Промокод %%%COUPON_NUMBER%%% 2 применения на карту":"%%%CARD_NUMBER%%%"}',NULL,'{}','asdf');
insert into coupon (id,code,action_id,placeholders) values (4,'vmeste2024',2,'{}');

insert into coupon_usage (coupon_id,card_number,uniq_key,shop_id,receipt_ts,status)
  values (4,1233,'cart5',10000000,null,'new');

insert into coupon_usage (coupon_id,card_number,uniq_key,shop_id,receipt_ts,status)
  values (4,1234,'cart6',10000000,null,'new');

insert into coupon_usage (coupon_id,card_number,uniq_key,shop_id,receipt_ts,status)
values (4,1235,'receipt2',1,'2024-10-10','accepted');

insert into coupon_usage (coupon_id,card_number,uniq_key,shop_id,receipt_ts,status)
values (4,1236,'receipt3',1,'2024-10-10','accepted');



-- Акция по карте. Даты могут быть в coupon для карты

insert into actions_v2
         (id,status, type,   start_date,  end_date,   `limit`, action_body,options,addr,bmp_fld)
  values (3,'run', 'card','2024-01-01','2030-01-01',1,'{"Акция по карте  %%%CARD_NUMBER%%% 1 применение на карту. Скидка 5%":"Привет %%%NAME%%%"}',NULL,'{}','asdf');
insert into coupon (id, code, action_id, placeholders) values (6,'5465',3,'{"NAME": "Петров Б."}');
insert into coupon (id, code, action_id, placeholders) values (5,'5464',3,'{"NAME": "Иванов А."}');
insert into coupon (id, code, action_id, placeholders) values (7,'5466',3,'{"NAME": "Сидоров В."}');


insert into coupon_usage (coupon_id, card_number, uniq_key, shop_id, receipt_ts, status)
values (5, 5464, 'cart1', 1, '2024-10-10', 'new');
insert into coupon_usage (coupon_id, card_number, uniq_key, shop_id, receipt_ts, status)
values (6, 5465, 'receipt4', 1, '2024-10-10', 'accepted');

