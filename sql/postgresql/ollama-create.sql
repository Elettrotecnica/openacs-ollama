begin;

CREATE EXTENSION if not exists vector;

create table ollama_ts_index (
   index_id bigserial primary key,
   object_id integer not null references acs_objects(object_id) on delete cascade,
   content text not null,
   embedding vector
);

--
-- This index has the same embedding dimensions as the popular
-- https://huggingface.co/sentence-transformers/all-MiniLM-L6-v2
--
CREATE INDEX ollama_ts_index_384 ON ollama_ts_index USING hnsw ((embedding::vector(384)) vector_cosine_ops);

end;
