
-- Акция по Купону. Даты в actions_v2, привязки к картам нет.

insert into actions_v2 (id,status,type,   start_date,  end_date,   `limit`,action_body,options,addr,bmp_fld)
 values (1,'run',  'coupon','2024-01-01','2030-01-01',5, '{"var1 %%%COUPON_VAR%%%":"Купон %%%COUPON_NUMBER%%% для карты %%%CARD_NUMBER%%% по акции %%%ACTION_ID%%% %%%START_DATE%%% %%%END_DATE%%%", "aId":1}',
        NULL,'{}',
        from_base64(
"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
KGTEOQoZcY5CRpyjkBHnKGTEOQoZcY5CRpyjkBHnKGTEOQoZcY5CRpyjkBHnKGTEOQoZcY5CRpyj
kBHnKGTEOQoZcY5CRpyjkBHnKGTEOQoZcY5CRpyjkBHnKGTEOQoZcY5CRpyjkBHnKGTEOQoZcY5C
RpyjkBHnKGTEOQoZcY5CRpyjkBHnKGTEOQoZcY5CRpyjkBHnKGTEOQoZcY5CRpyjkBHnKGTEOQoZ
cY5CRpyjkBHnKGTEOQoZcY5CRpyjkBHnKGTEOQoZcY5CRpyjkBHnKGTEOQoZcY5CRpyjkBHnKGTE
OQoZcY5CRpyjkBHnKGTEOQoZcY5CRpyjkBHnKGTEOQoZcY5CRpyjkBHnKGTEOQoZcY5CRpyjkBHn
KGTEOQoZcY5CRpyjkBHnKGTEOQoZcY5CRpyjkBHnKGTEOQoZcY5CRpyjkBHnKGTEOQoZcY5CRpyj
kBHnKGTEOQoZcY5CRpyjkBHnKGTEOQoZcY5CRpyjkBHnKGTEOQoZcY5CRpyjkBHnKGTEOQoZcY5C
RpyjkBHnKGTEuf8PuXvkBvNG+w8AAADNZVhJZklJKgAIAAAAAwAOAQIAiwAAADIAAAAaAQUAAQAA
AL0AAAAbAQUAAQAAAMUAAAAAAAAAUGljdHVyZSBpY29uLiBQaG90byBmcmFtZSBzeW1ib2wuIExh
bmRzY2FwZSBzaWduLiBQaG90b2dyYXBoIGdhbGxlcnkgbG9nby4gV2ViIGludGVyZmFjZSBhbmQg
YXBwbGljYXRpb24gYnV0dG9uLiBWZWN0b3IgaWxsdXN0cmF0aW9uIGltYWdlLiwBAAABAAAALAEA
AAEAAADMwsCEAAAAJXRFWHRkYXRlOmNyZWF0ZQAyMDI1LTAxLTE2VDA3OjI1OjEzKzAwOjAwerTd
EwAAACV0RVh0ZGF0ZTptb2RpZnkAMjAyNS0wMS0xNlQwNzoyMToyMCswMDowML1l2KsAAACHelRY
dGV4aWY6SW1hZ2VEZXNjcmlwdGlvbgAACJk1jbENwzAMBFf5CTRJCldJTTG0TIASBYouvH0cBGn/
7vCbcp4hUPZRsB2ejj2oC9bVq1vBg8Z7Mc170fZ3WtA80MhM4oJ584KXVOhIiZ1YcFegOU2ZUn2g
npnfi6dwekDNzpXxY9qpSfkA3pwzMOOQP8MAAAAASUVORK5CYII="
));




insert into coupon (id,code,action_id,placeholders) values (1,'121',1,'{"COUPON_VAR": 1}');
insert into coupon (id,code,action_id,placeholders)
values (2,'122',1,'{"COUPON_VAR": 2}');
insert into coupon (id,code,action_id,placeholders)
values (3,'123',1,'{"COUPON_VAR": 3}');
--  
-- применения  купона № 1 в интернет аптеке
insert into coupon_usage (coupon_id,card_number,uniq_key,shop_id,receipt_ts,status)
  values (1,5464,'cart1', 1000000, null,'new');
insert into coupon_usage (coupon_id,card_number,uniq_key,shop_id,receipt_ts,status)
  values (2,0,'cart2', 1000000, null,'holdout');

-- применения  купона № 1 в магазине
insert into coupon_usage (coupon_id,card_number,uniq_key,shop_id,receipt_ts,status)
  values (1,0,'receipt1',1,'2024-10-10','accepted');


-- применения  купона № 3, лимит выбран
insert into coupon_usage (coupon_id,card_number,uniq_key,shop_id,receipt_ts,status)
  values (3,0,'cart3', 1000000, null,'holdout');
insert into coupon_usage (coupon_id,card_number,uniq_key,shop_id,receipt_ts,status)
  values (3, 0, 'cart4', 1000000, null,'holdout');
insert into coupon_usage (coupon_id,card_number,uniq_key,shop_id,receipt_ts,status)
  values (3,0,'rec1',1,'2024-10-10','accepted');
insert into coupon_usage (coupon_id,card_number,uniq_key,shop_id,receipt_ts,status)
  values (3,0,'rec2',1,'2024-10-10','accepted');
insert into coupon_usage (coupon_id,card_number,uniq_key,shop_id,receipt_ts,status)
  values (3,0,'rec3',1,'2024-10-10','accepted');


-- Акция по промокоду. Одно применение  на карту
insert into actions_v2 (id, status,type, start_date, end_date,   `limit`,action_body,options,addr,bmp_fld)
  values (2,'run',  'promocode','2024-01-01','2030-01-01',3,
          '{"%%%CARD_NUMBER%%%":"Промокод %%%COUPON_NUMBER%%% 2 применения на карту","aId":2}',NULL,'{}','asdf');
insert into coupon (id,code,action_id,placeholders)
  values (4,'vmeste2024',2,'{}');

insert into coupon_usage (coupon_id,card_number,uniq_key,shop_id,receipt_ts,status)
  values (4, 1233, 'cart5',10000000,null,'new');

insert into coupon_usage (coupon_id,card_number,uniq_key,shop_id,receipt_ts,status)
  values (4,1234,'cart6',10000000,null,'new');

insert into coupon_usage (coupon_id,card_number,uniq_key,shop_id,receipt_ts,status)
  values (4,1235,'receipt2',1,'2024-10-10','accepted');

insert into coupon_usage (coupon_id,card_number,uniq_key,shop_id,receipt_ts,status)
  values (4,1236,'receipt3',1,'2024-10-10','accepted');


-- Акция по карте. Даты могут быть в coupon для карты

insert into actions_v2
         (id,status, type,   start_date,  end_date,   `limit`, action_body,options,addr,bmp_fld)
    values (3,'run', 'card','2024-01-01','2030-01-01',1,
            '{"Привет %%%NAME%%%":"Акция по карте %%%CARD_NUMBER%%% 1 применение на карту. Скидка 5%","aId":3}',NULL,'{}','asdf');

insert into coupon (id, code, action_id, placeholders) values (6,'5465',3,'{"NAME": "Петров Б."}');
insert into coupon (id, code, action_id, placeholders) values (5,'5464',3,'{"NAME": "Иванов А."}');
insert into coupon (id, code, action_id, placeholders) values (7,'5466',3,'{"NAME": "Сидоров В."}');


insert into coupon_usage (coupon_id, card_number, uniq_key, shop_id, receipt_ts, status)
values (5, 5464, 'cart1', 1, NULL, 'new');
insert into coupon_usage (coupon_id, card_number, uniq_key, shop_id, receipt_ts, status)
values (6, 5465, 'receipt4', 1, '2024-10-10', 'accepted');


-- Акция по карте draft
insert into actions_v2
         (id,status, type,   start_date,  end_date,   `limit`, action_body,options,addr,bmp_fld)
    values (4,'draft', 'card','2024-01-01','2030-01-01',1,
            '{"Привет %%%NAME%%%":"Акция по карте %%%CARD_NUMBER%%% 1 применение на карту. Скидка 5%","aId":4}',NULL,'{}','asdf');
insert into coupon (id, code, action_id, placeholders) values (8,'5465',4,'{"NAME": "Петров Б."}');
-- insert into coupon (id, code, action_id, placeholders) values (9,'5464',4,'{"NAME": "Иванов А."}');
insert into coupon (id, code, action_id, placeholders) values (10,'5466',4,'{"NAME": "Сидоров В."}');

-- Акция по карте просрочена
insert into actions_v2
         (id,status, type,   start_date,  end_date,   `limit`, action_body,options,addr,bmp_fld)
    values (5,'draft', 'card','2024-01-01','2024-01-30',1,
            '{"Привет %%%NAME%%%":"Акция по карте %%%CARD_NUMBER%%% 1 применение на карту. Скидка 5%","aId":5}',NULL,'{}','asdf');
insert into coupon (id, code, action_id, placeholders) values (11,'5465',5,'{"NAME": "Петров Б."}');
-- insert into coupon (id, code, action_id, placeholders) values (12,'5464',5,'{"NAME": "Иванов А."}');
insert into coupon (id, code, action_id, placeholders) values (13,'5466',5,'{"NAME": "Сидоров В."}');

insert into coupon_usage (coupon_id, card_number, uniq_key, shop_id, receipt_ts, status)
values (12, 5464, 'cart5', 1, NULL, 'new');
insert into coupon_usage (coupon_id, card_number, uniq_key, shop_id, receipt_ts, status)
values (11, 5465, 'receipt5', 1, '2024-01-10', 'accepted');
