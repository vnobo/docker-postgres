-- Create the zhparser extension (idempotent).
create extension if not exists zhparser;

-- Register a Chinese text search configuration (idempotent).
drop text search configuration if exists chinese;
create text search configuration chinese (parser = zhparser);

-- Map token types to the simple dictionary.
alter text search configuration chinese add mapping for n,v,a,i,e,l,x with simple;
set default_text_search_config = 'chinese';
show default_text_search_config;

-- Add and sync custom words (idempotent).
do $$
begin
  if not exists (select 1 from zhparser.zhprs_custom_word where word = '支付宝') then
    insert into zhparser.zhprs_custom_word values ('支付宝');
  end if;
  if not exists (select 1 from zhparser.zhprs_custom_word where word = '资金压力') then
    insert into zhparser.zhprs_custom_word values ('资金压力');
  end if;
end $$;
select sync_zhprs_custom_word();
alter extension zhparser update;

-- Inspect supported token types.
select ts_token_type('zhparser');

-- Debug Chinese segmentation.
select ts_debug('chinese', '支付宝使用很方便');
select ts_debug('chinese', '保障房资金压力');

-- Test custom-word parsing.
select ts_parse('zhparser', '支付宝使用很方便');
select ts_parse('zhparser', '保障房资金压力');

-- Test to_tsvector / to_tsquery.
select to_tsvector('chinese', '支付宝使用很方便');
select to_tsquery('chinese', '支付宝使用很方便');
select to_tsvector('chinese', '保障房资金压力');
select to_tsquery('chinese', '保障房资金压力');
