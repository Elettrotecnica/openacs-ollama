# Ollama integration for OpenACS

This package provides integration with [Ollama](https://ollama.com/) in OpenACS.

## Main features

* Complete wrapper for the [Ollama API](https://github.com/ollama/ollama/blob/main/docs/api.md), including streaming response.
* Implements the FtsEngineDriver contract. You can use semantic embedding-based indexing to search into your documents.
* RAG implementation. Use the indexed data from your packages (file-storage, xowiki, forums...) to inquire the model.
* RAG from web search. Optionally, one can use the query as a web search to provide additional context to the model.

## Dependencies

* NaviServer >= 5.0 with [ns_http -response_data_callback feature](https://naviserver.sourceforge.io/5.0/naviserver/files/ns_http.html)
* Postgres databse
* [PgVector](https://github.com/pgvector/pgvector) extension must be available.
* An Ollama instance accessible by the OpenACS installation.

## Usage as an FTS driver

* Install the package
* Ensure search is mounted
* set "ollama-driver" as value for the FtsEngineDriver parameter in the search package
* if your existance already used full-text-search in the past with a different driver, you can bootstrap the new ollama index by calling the *ollama::bootstrap_index* proc. On a system with a lot of data, this could take a long time, so you may need to schedule this accordingly.

## How does indexing work?

The search package converts every document implementing the FtsEngineDriver contract into a text representation. We split this text into slightly overlapping chunks and create an index entry for each of them. For every such entry, we generate the corresponding embedding via ollama.

Upon search, the search query is also transformed into an embedding, and used to retrieve all relevant entries by comparing the vector distance between query and indexed chunks. We use pg_vector for this.

## How does RAG work?

Retrieval Augmented Generation is a popular technique used to inject on-the-fly topic knowledge into a conversation with an LLM. Instead of training a new model with domain knowledge, we use the query to perform an index search, then use the retrieved knowledge to generate a new question that includes this relevant information for the model to use when replying to us.

The way RAG is implemented in this package is the following: regardless of whether you are using the ollama-driver for full-text-search, searchable packages such as file-storage, xowiki, forums and so on that are mounted underneath an ollama instance will be indexed. They will be treated as a "knowledge base" for their parent package.

We then implemented a "chat-like" UI where questions to the selected model will be enhanced by our knowledge whenever relevant information is found.

As many models will output markdown when replying to the user, we have also integrated on-the-fly markdown-to-html conversion via the [Showdown](https://showdownjs.com/) library.

## Possible TODOs

* images in RAG conversations
* support for index bootsrap/reindexing in the UI
* ...and much more
