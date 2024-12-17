#
# Batch-generate embeddings for entries in the index every 30s.
#
ad_schedule_proc -thread t 30 ollama::batch_index

ad_schedule_proc -thread t 60 ollama::index_instance_descendants
