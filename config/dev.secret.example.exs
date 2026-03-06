import Config

config :zaq, :super_admin,
  username: "admin",
  password: "admin"

# -- Agent LLM --
config :zaq, Zaq.Agent.LLM,
  endpoint: "http://localhost:11434/v1",
  api_key: "",
  model: "llama3.2:latest",
  temperature: 0.0,
  top_p: 0.9,
  supports_logprobs: "true" == "true",
  supports_json_mode: "true" == "true"

# -- Embedding --
config :zaq, Zaq.Embedding.Client,
  endpoint: "http://localhost:11434/v1",
  api_key: "",
  model: "nomic-embed-text:latest",
  dimension: String.to_integer("768")

# -- Ingestion --
config :zaq, Zaq.Ingestion,
  max_context_window: String.to_integer("5000"),
  distance_threshold: String.to_float("0.75"),
  hybrid_search_limit: String.to_integer("20"),
  chunk_min_tokens: String.to_integer("400"),
  chunk_max_tokens: String.to_integer("900"),
  base_path: "priv/documents"
