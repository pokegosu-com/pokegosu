-- The Lv.100 ribbon is named for the work it took, not the number reached.

update public.coder_ribbons
   set ko_name = '성실 리본', en_name = 'Diligence Ribbon'
 where id = 'level-100';
