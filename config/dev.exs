use Mix.Config

# config :elixir, :time_zone_database, Tzdata.TimeZoneDatabase

config :logger,
  backends: [{LoggerFileBackendWin, :dev_backend}],
  level: :info,
  format: "$time $metadata[$level] $message\n"

config :logger, :dev_backend,
  level: :error,
  path: "test/logs",
  filename: "logger_file_backend_win",
  format: "DEV $message"
