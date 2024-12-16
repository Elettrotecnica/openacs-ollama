drop table if exists ollama_ts_index;

drop table if exists ollama_conversation_messages;

drop table if exists ollama_conversations;

select acs_object_type__drop_type('ollama_conversation', 't');
