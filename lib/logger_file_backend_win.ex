defmodule LoggerFileBackendWin do
  @moduledoc """
  `LoggerFileBackend` is a custom backend for the elixir `:logger` application.
  """

  @behaviour :gen_event

  @type path :: String.t()
  @type dir :: String.t()
  @type filename :: String.t()
  @type file_num :: non_neg_integer()
  @type file :: :file.io_device()
  @type format :: String.t()
  @type level :: Logger.level()
  @type metadata :: [atom]

  require Record
  Record.defrecordp(:file_info, Record.extract(:file_info, from_lib: "kernel/include/file.hrl"))

  @default_format "$time $metadata[$level] $message\n"

  def init({__MODULE__, name}) do
    send_date_rotate(local_date())
    {:ok, configure(name, [])}
  end

  def handle_call({:configure, opts}, %{name: name} = state) do
    {:ok, :ok, configure(name, opts, state)}
  end

  def handle_call(:path, %{path: path} = state) do
    {:ok, {:ok, path}, state}
  end

  def handle_call(
        {:path_for_file_num, file_num},
        %{dir: dir, filename: filename, date: date} = state
      ) do
    {:ok, {:ok, path(dir, filename, date, file_num)}, state}
  end

  def handle_event(
        {level, _gl, {Logger, msg, ts, md}},
        %{level: min_level, metadata_filter: metadata_filter} = state
      ) do
    if (is_nil(min_level) or Logger.compare_levels(level, min_level) != :lt) and
         metadata_matches?(md, metadata_filter) do
      log_event(level, msg, ts, md, state)
    else
      {:ok, state}
    end
  end

  def handle_event(:flush, state) do
    # We're not buffering anything so this is a no-op
    {:ok, state}
  end

  def handle_info(
        :date_rotate,
        %{
          dir: dir,
          filename: filename,
          file_num: file_num,
          date: date,
          rotate: %{keep: keep}
        } = state
      ) do
    today = local_date()

    if Date.compare(today, date) == :gt do
      delete_old_files(dir, filename, file_num, date, keep)
      send_date_rotate(today)
      {:ok, %{state | date: today, file_num: 0, path: path(dir, filename, today, 0)}}
    else
      send_date_rotate(date)
      {:ok, state}
    end
  end

  def handle_info(_, state) do
    {:ok, state}
  end

  # helpers

  def send_date_rotate(date) do
    tomorrow = date |> Date.add(1) |> DateTime.new!(~T[00:00:00.000000])

    case DateTime.diff(tomorrow, local(), :millisecond) do
      t when t > 0 -> Process.send_after(self(), :date_rotate, t)
      _ -> send(self(), :date_rotate)
    end
  end

  defp log_event(_level, _msg, _ts, _md, %{path: nil} = state) do
    {:ok, state}
  end

  defp log_event(level, msg, ts, md, %{path: path, io_device: nil} = state)
       when is_binary(path) do
    case open_log(path) do
      {:ok, io_device} ->
        log_event(level, msg, ts, md, %{state | io_device: io_device})

      _other ->
        {:ok, state}
    end
  end

  defp log_event(
         level,
         msg,
         ts,
         md,
         %{
           file_num: file_num,
           io_device: io_device
         } = state
       ) do
    state = %{path: path} = rotate(state)

    if state[:file_num] == file_num and File.exists?(path) do
      output = format_event(level, msg, ts, md, state)

      try do
        IO.write(io_device, output)
        {:ok, state}
      rescue
        ErlangError ->
          case open_log(path) do
            {:ok, io_device} ->
              IO.write(io_device, prune(output))
              {:ok, %{state | io_device: io_device}}

            _other ->
              {:ok, %{state | io_device: nil}}
          end
      end
    else
      File.close(io_device)
      log_event(level, msg, ts, md, %{state | io_device: nil})
    end
  end

  defp rotate(
         %{
           path: path,
           rotate: %{max_bytes: max_bytes, keep: keep}
         } = state
       )
       when is_integer(max_bytes) and is_integer(keep) and keep > 0 do
    case :file.read_file_info(path, [:raw]) do
      {:ok, file_info(size: size)} when size >= max_bytes ->
        %{date: date, dir: dir, filename: filename, file_num: file_num} = state
        delete_old_files(dir, filename, file_num + 1, date, keep)
        %{state | file_num: file_num + 1, path: path(dir, filename, date, file_num + 1)}

      _ ->
        state
    end
  end

  defp rotate(state), do: state

  defp delete_old_files(_dir, _filename, _file_num, _date, nil), do: :ok

  defp delete_old_files(dir, filename, file_num, date, keep) do
    Enum.flat_map((file_num - keep)..0//-1, fn x ->
      path = path(dir, filename, date, x)

      case File.rm(path) do
        :ok -> [x]
        _ -> []
      end
    end)

    # if deleted == [] do
    #   :ok
    # else
    #   delete_files_for_date(dir, filename, date)
    # end
  end

  # defp delete_files_for_date(dir, filename, date) do
  #   case File.ls(dir) do
  #     {:ok, files} ->
  #       files
  #       |> Enum.filter(&String.match?(&1, ~r/#{filename}_#{Date.to_string(date)}(\.\d+)?\.log/))
  #       |> Enum.map(&File.rm(Path.join(dir, &1)))
  #       |> Enum.count()
  #       |> case do
  #         0 -> false
  #         _ -> delete_files_for_date(dir, filename, Date.add(date, -1))
  #       end

  #     _ ->
  #       false
  #   end
  # end

  defp open_log(path) do
    case path |> Path.dirname() |> File.mkdir_p() do
      :ok ->
        case File.open(path, [:append, :utf8]) do
          {:ok, io_device} -> {:ok, io_device}
          other -> other
        end

      other ->
        other
    end
  end

  defp path(dir, filename, date, file_num)
       when is_nil(dir) or is_nil(filename) or is_nil(date) or is_nil(file_num) do
    nil
  end

  defp path(dir, filename, date, file_num) do
    "#{Path.join(dir, filename)}_#{Date.to_string(date)}.#{file_num}.log"
  end

  defp format_event(level, msg, ts, md, %{format: format, metadata: keys}) do
    Logger.Formatter.format(format, level, msg, ts, take_metadata(md, keys))
  end

  @doc false
  @spec metadata_matches?(Keyword.t(), nil | Keyword.t()) :: true | false
  def metadata_matches?(_md, nil), do: true
  # all of the filter keys are present
  def metadata_matches?(_md, []), do: true

  def metadata_matches?(md, [{key, [_ | _] = val} | rest]) do
    case Keyword.fetch(md, key) do
      {:ok, md_val} ->
        md_val in val && metadata_matches?(md, rest)

      # fail on first mismatch
      _ ->
        false
    end
  end

  def metadata_matches?(md, [{key, val} | rest]) do
    case Keyword.fetch(md, key) do
      {:ok, ^val} ->
        metadata_matches?(md, rest)

      # fail on first mismatch
      _ ->
        false
    end
  end

  defp take_metadata(metadata, :all), do: metadata

  defp take_metadata(metadata, keys) do
    metadatas =
      Enum.reduce(keys, [], fn key, acc ->
        case Keyword.fetch(metadata, key) do
          {:ok, val} -> [{key, val} | acc]
          :error -> acc
        end
      end)

    Enum.reverse(metadatas)
  end

  defp configure(name, opts) do
    state = %{
      name: nil,
      dir: nil,
      path: nil,
      filename: nil,
      io_device: nil,
      format: nil,
      level: nil,
      metadata: nil,
      metadata_filter: nil,
      rotate: nil,
      file_num: nil,
      date: nil
    }

    configure(name, opts, state)
  end

  defp configure(name, opts, state) do
    env = Application.get_env(:logger, name, [])
    opts = Keyword.merge(env, opts)
    Application.put_env(:logger, name, opts)

    level = Keyword.get(opts, :level)
    metadata = Keyword.get(opts, :metadata, [])
    format_opts = Keyword.get(opts, :format, @default_format)
    format = Logger.Formatter.compile(format_opts)
    dir = Keyword.get(opts, :path, ".")
    filename = Keyword.get(opts, :filename, "log")
    metadata_filter = Keyword.get(opts, :metadata_filter)
    rotate = Keyword.get(opts, :rotate)
    date = local_date()
    file_num = next_file_num(dir, filename, date)
    path = path(dir, filename, date, file_num)

    %{
      state
      | name: name,
        dir: dir,
        path: path,
        filename: filename,
        format: format,
        level: level,
        metadata: metadata,
        metadata_filter: metadata_filter,
        rotate: rotate,
        file_num: file_num,
        date: date
    }
  end

  defp local do
    DateTime.add(DateTime.utc_now(), tz_offset())
  end

  defp local_date do
    DateTime.to_date(local())
  end

  defp tz_offset do
    case :os.type() do
      {:win32, :nt} ->
        {result, 0} = System.cmd("w32tm", ["/tz"])

        [bias] =
          Regex.run(
            ~r/Bias: (.*)min \(UTC=LocalTime\+Bias\)/,
            result,
            capture: :all_but_first
          )

        String.to_integer(bias) * 60

      _ ->
        raise "OS not supported!"
    end
  end

  defp next_file_num(nil, _filename, _date), do: 0

  defp next_file_num(dir, filename, date) do
    case File.ls(dir) do
      {:ok, files} ->
        date_str = Date.to_string(date)

        largest_file_num =
          files
          |> Enum.flat_map(fn f ->
            case Regex.run(~r/#{filename}_#{date_str}\.(\d+)\.log/, f, capture: :all_but_first) do
              [n] -> [String.to_integer(n)]
              nil -> []
            end
          end)
          |> Enum.sort(:desc)
          |> Enum.take(1)

        case largest_file_num do
          [n] -> n + 1
          [] -> 0
        end

      {:error, _} ->
        0
    end
  end

  @replacement "�"

  @spec prune(IO.chardata()) :: IO.chardata()
  def prune(binary) when is_binary(binary), do: prune_binary(binary, "")
  def prune([h | t]) when h in 0..1_114_111, do: [h | prune(t)]
  def prune([h | t]), do: [prune(h) | prune(t)]
  def prune([]), do: []
  def prune(_), do: @replacement

  defp prune_binary(<<h::utf8, t::binary>>, acc),
    do: prune_binary(t, <<acc::binary, h::utf8>>)

  defp prune_binary(<<_, t::binary>>, acc),
    do: prune_binary(t, <<acc::binary, @replacement>>)

  defp prune_binary(<<>>, acc),
    do: acc
end
