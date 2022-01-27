# LoggerFileBackendWin

A simple Elixir `Logger` backend for Windows, which writes logs to a file. It can rotate files at the start of each new day (local time) and when a maximum size is reached, if you wish it to be so.

**Note** If you are running this with the Phoenix framework, please review the Phoenix specific instructions later on in this file.

## Configuration

`LoggerFileBackendWin` is a custom backend for the elixir `:logger` application. As
such, it relies on the `:logger` application to start the relevant processes.
However, unlike the default `:console` backend, we may want to configure
multiple log files, each with different log levels, formats, etc. Also, we want
`:logger` to be responsible for starting and stopping each of our logging
processes for us. Because of these considerations, there must be one `:logger`
backend configured for each log file we need. Each backend has a name like
`{LoggerFileBackendWin, name}`, where `name` is any elixir term (usually an atom).

For example, let's say we want to log error messages to
`"<APPDIR>/logs/error_log_<DATE>.<FILE#>.log"`. To do that, we will need to configure a backend.

Our `config.exs` would have an entry similar to this:

```elixir
# tell logger to load a LoggerFileBackend processes
config :logger,
  backends: [{LoggerFileBackendWin, :error_log}]
```

With this configuration, the `:logger` application will start one `LoggerFileBackendWin`
named `{LoggerFileBackendWin, :error_log}`. We still need to set the correct file
path and log levels for the backend, though. To do that, we add another config
stanza. Together with the stanza above, we'll have something like this:

```elixir
# tell logger to load a LoggerFileBackend processes
config :logger,
  backends: [{LoggerFileBackendWin, :error_log}]

# configuration for the {LoggerFileBackend, :error_log} backend
config :logger, :error_log,
  dir: "logs",
  level: :error
```

This will use the `name` defined in the backend configuration for the filename.  You can
set a custom name using the `filename` option.  The complete filename looks like:
`"#{dir}/#{filename}_#{Date.to_string(date).#{file_number}.log"`.  The file number starts
at `0` and newer ones are incremented by one.  We do not rename them, the highest number 
is always the most recent.

`LoggerFileBackendWin` supports the following configuration values:

* `dir` - the directory where log files are saved
* `filename` - the file name to write to
* `level` - the logging level for the backend
* `format` - the logging format for the backend
* `metadata` - the metadata to include
* `metadata_filter` - metadata terms which must be present in order to log
* `rotate` - file rotation configuration

### Directory

`dir` accepts a string or a tuple `{:user_data|:user_log, app, opts}`, where opts can include `author` and/or `version`.
This will output logs to `C:/Users/<user>/AppData/Local/[author/]<app>/[version/]` for `:user_data` or `C:/Users/<user>/AppData/Local/[author/]<app>/[version/]Logs` for `:user_log`.

### File Rotation

```elixir
config :logger, :error_log,
  dir: "logs",
  level: :error,
  rotate: %{
    daily: true,
    days: 30,
    keep: 3,
    max_bytes: 1_000_000
  }
```

The above configuration will:

* rotate files daily
* keep 30 days worth of logs
* create a new log file once the current one exceeds `max_bytes`
* keeping up to `3` x `1,000,000` byte files for each day

So you'll end up with something like this:

```
error_log_2021-06-18.1.log
error_log_2021-06-18.0.log

error_log_2021-06-17.0.log

error_log_2021-06-16.2.log
error_log_2021-06-16.1.log
error_log_2021-06-16.0.log
```

### Examples

#### Runtime configuration

```elixir
Logger.add_backend {LoggerFileBackend, :debug}
Logger.configure_backend {LoggerFileBackend, :debug},
  dir: "/path/to",
  filename: "debug"
  format: ...,
  metadata: ...,
  metadata_filter: ...
```

#### Application config for multiple log files

```elixir
config :logger,
  backends: [{LoggerFileBackendWin, :info},
             {LoggerFileBackendWin, :error}]

config :logger, :info,
  level: :info

config :logger, :error,
  level: :error
```

#### Filtering specific metadata terms

This example only logs `:info` statements originating from the `:ui` OTP app; the `:application` metadata key is auto-populated by `Logger`.

```elixir
config :logger,
  backends: [{LoggerFileBackendWin, :ui}]

config :logger, :ui,
  level: :info,
  metadata_filter: [application: :ui]
```

This example only writes log statements with a custom metadata key to the file.

```elixir
# in a config file:
config :logger,
  backends: [{LoggerFileBackendWin, :device_1}]

config :logger, :device_1,
  level: :debug,
  metadata_filter: [device: 1]

# Usage:
# anywhere in the code:
Logger.info("statement", device: 1)

# or, for a single process, e.g., a GenServer:
# in init/1:
Logger.metadata(device: 1)
# ^ sets device: 1 for all subsequent log statements from this process.

# Later, in other code (handle_cast/2, etc.)
Logger.info("statement") # <= already tagged with the device_1 metadata
```

## Additional Phoenix Configurations

Phoenix makes use of its own `mix.exs` file to track dependencies and additional applications. Add the following to your `mix.exs`:

```elixir
def application do
    [applications: [
      ...,
      :logger_file_backend_win,
      ...
      ]
    ]
end
  
defp deps do
  [ 
    ...
    {:logger_file_backend_win, "~> 0.0.2"},
    ...
  ]
end
```

###  Attribution

This project is little more than [logger_file_backend](https://github.com/onkel-dirtus/logger_file_backend) modified to rotate files on Windows.
