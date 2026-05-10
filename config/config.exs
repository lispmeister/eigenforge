import Config

config :eigenforge_core,
  hmac_secret: System.get_env("EIGENFORGE_HMAC_SECRET") || "eigenforge-v1-test-secret",
  reasoner_module: Eigenforge.Core.Reasoners.Co2Rules
