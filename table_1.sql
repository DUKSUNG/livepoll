#!/usr/bin/python
#*-* coding: USF8-*-
insert into table_1 (time,KBS2,MBC,SBS) values (19, '뻐꾸기둥지', '소원을 말해봐', '사랑만 할래');
insert into table_1 (time,KBS2,MBC,SBS) values (20, '생생정보통 플러스', '압구정백야', '생활의 달인');
insert into table_1 (time,KBS2,MBC,SBS) values (21, '', '리얼스토리 눈', '');
insert into table_1 (time,KBS2,MBC,SBS) values (22, '연애의 발견', '야경꾼 일지', '비밀의 문');
insert into table_1 (time,KBS2,MBC,SBS) values (23, '대국민 토크쇼 안녕하세요', 'MBC 다큐스페셜', '힐링캠프');
update table_1 set SBS='UPDATE' where time=21;
delete from table_1 where time=19;

