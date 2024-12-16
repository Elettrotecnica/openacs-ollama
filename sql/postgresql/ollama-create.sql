begin;

CREATE EXTENSION if not exists vector;

create table ollama_ts_index (
   index_id bigserial primary key,
   object_id integer not null references acs_objects(object_id) on delete cascade,
   content text not null,
   embedding vector
);

CREATE INDEX ollama_ts_index_object_id_idx ON
       ollama_ts_index(object_id);

--
-- This index has the same embedding dimensions as the popular
-- https://huggingface.co/sentence-transformers/all-MiniLM-L6-v2
--
CREATE INDEX ollama_ts_index_embedding_384_idx ON
       ollama_ts_index USING hnsw ((embedding::vector(384)) vector_cosine_ops);

select acs_object_type__create_type (
    'ollama_conversation',
    'Conversation',
    'Conversations',
    'acs_object',
    'ollama_conversations',
    'conversation_id',
    null,
    'f',
    null,
    null
);

create table ollama_conversations (
       conversation_id integer
                       primary key
                       references acs_objects(object_id)
                       on delete cascade
);

create table ollama_conversation_messages (
       message_id bigserial primary key,
       conversation_id integer not null
                       references ollama_conversations(conversation_id)
                       on delete cascade,
       timestamp timestamp not null default current_timestamp,
       role text not null,
       content text,
       rag text,
       model text
);

CREATE INDEX ollama_conversation_messages_conversation_id_idx ON
       ollama_conversation_messages(conversation_id);

end;
