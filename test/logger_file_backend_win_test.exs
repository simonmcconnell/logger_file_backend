defmodule LoggerFileBackendWinTest do
  use ExUnit.Case, async: false
  require Logger

  @backend {LoggerFileBackendWin, :test}
  @basedir "test/logs"
  @author "YeahNah_NahYeah-Nah__BananaTown1974 Swamp Wallaby"
  @app "LoggerFileBackendWin"
  @version "20.1.2"

  import LoggerFileBackendWin, only: [prune: 1, metadata_matches?: 2]

  setup_all do
    on_exit(fn ->
      File.rm_rf!(@basedir)
      File.rm_rf!(local_app_data_dir())
    end)
  end

  setup context do
    # We add and remove the backend here to avoid cross-test effects
    Logger.add_backend(@backend, flush: true)

    config(dir: @basedir, filename: logfile(context), level: :debug)

    on_exit(fn ->
      :ok = Logger.remove_backend(@backend)
    end)
  end

  test "does not crash if dir isn't set" do
    config(dir: nil)

    Logger.debug("foo")
    assert {:error, :already_present} = Logger.add_backend(@backend)
  end

  test "can configure metadata_filter" do
    config(metadata_filter: [md_key: true])
    Logger.debug("shouldn't", md_key: false)
    Logger.debug("should", md_key: true)
    refute log() =~ "shouldn't"
    assert log() =~ "should"
    config(metadata_filter: nil)
  end

  test "metadata_matches?" do
    # exact match
    assert metadata_matches?([a: 1], a: 1) == true
    # included in array match
    assert metadata_matches?([a: 1], a: [1, 2]) == true
    # total mismatch
    assert metadata_matches?([b: 1], a: 1) == false
    # default to allow
    assert metadata_matches?([b: 1], nil) == true
    # metadata is superset of filter
    assert metadata_matches?([b: 1, a: 1], a: 1) == true
    # multiple filter keys subset of metadata
    assert metadata_matches?([c: 1, b: 1, a: 1], b: 1, a: 1) == true
    # multiple filter keys superset of metadata
    assert metadata_matches?([a: 1], b: 1, a: 1) == false
  end

  test "creates log file" do
    refute File.exists?(path())
    Logger.debug("this is a msg")
    assert File.exists?(path())
    assert log() =~ "this is a msg"
  end

  test "can log utf8 chars" do
    Logger.debug("ß\uFFaa\u0222")
    assert log() =~ "ßﾪȢ"
  end

  test "prune/1" do
    assert prune(1) == "�"
    assert prune(<<"hí", 233>>) == "hí�"
    assert prune(["hi" | 233]) == ["hi" | "�"]
    assert prune([233 | "hi"]) == [233 | "hi"]
    assert prune([[] | []]) == [[]]
  end

  test "prunes invalid utf-8 codepoints" do
    Logger.debug(<<"hi", 233>>)
    assert log() =~ "hi�"
  end

  test "can configure format" do
    config(format: "$message [$level]\n")

    Logger.debug("hello")
    assert log() =~ "hello [debug]"
  end

  test "can configure metadata" do
    config(format: "$metadata$message\n", metadata: [:user_id, :auth])

    Logger.debug("hello")
    assert log() =~ "hello"

    Logger.metadata(auth: true)
    Logger.metadata(user_id: 11)
    Logger.metadata(user_id: 13)

    Logger.debug("hello")
    assert log() =~ "user_id=13 auth=true hello"
  end

  test "can configure level" do
    config(level: :info)

    Logger.debug("hello")
    refute File.exists?(path())
  end

  test "can configure dir" do
    new_dir = "test/logs/test2/"
    config(dir: new_dir)
    assert Path.dirname(new_dir) == Path.dirname(path())
  end

  test "can configure filename" do
    new_filename = "new-filename"
    config(filename: new_filename)
    assert new_filename == String.slice(Path.basename(path(), ".0.log"), 0..-12//1)
  end

  test "logs to new file after old file has been moved" do
    config(format: "$message\n")

    Logger.debug("foo")
    Logger.debug("bar")
    assert log() == "foo\nbar\n"

    {"", 0} = System.cmd("mv", [path(), path_for_file_num(1)])

    Logger.debug("biz")
    Logger.debug("baz")
    assert log() == "biz\nbaz\n"
  end

  test "log file rotate" do
    config(format: "$message\n")
    config(rotate: %{max_bytes: 4, keep: 4})

    Logger.debug("rotate0")
    Logger.debug("rotate1")
    Logger.debug("rotate2")
    Logger.debug("rotate3")
    Logger.debug("rotate4")
    Logger.debug("rotate5")

    refute File.exists?("#{path_for_file_num(0)}")
    refute File.exists?("#{path_for_file_num(1)}")
    assert File.read!("#{path_for_file_num(2)}") == "rotate2\n"
    assert File.read!("#{path_for_file_num(3)}") == "rotate3\n"
    assert File.read!("#{path_for_file_num(4)}") == "rotate4\n"
    assert File.read!(path()) == "rotate5\n"

    config(rotate: nil)
  end

  test "log file not rotate" do
    config(format: "$message\n")
    config(rotate: %{max_bytes: 100, keep: 4})

    words = ~w(rotate1 rotate2 rotate3 rotate4 rotate5 rotate6)
    words |> Enum.map(&Logger.debug(&1))

    assert log() == Enum.join(words, "\n") <> "\n"

    config(rotate: nil)
  end

  test "Allow :all to metadata" do
    config(format: "$metadata")

    config(metadata: [])
    Logger.debug("metadata", metadata1: "foo", metadata2: "bar")
    assert log() == ""

    config(metadata: [:metadata3])
    Logger.debug("metadata", metadata3: "foo", metadata4: "bar")
    assert log() == "metadata3=foo "

    config(metadata: :all)
    Logger.debug("metadata", metadata5: "foo", metadata6: "bar")

    # Match separately for metadata5/metadata6 to avoid depending on order
    contents = log()
    assert contents =~ "metadata5=foo"
    assert contents =~ "metadata6=bar"
  end

  test "logs to :user_data" do
    config(dir: {:user_data, @app, author: @author, version: @version})
    assert local_app_data_dir() == Path.dirname(path())
  end

  test "logs to :user_log" do
    config(dir: {:user_log, @app, author: @author, version: @version})
    assert Path.join(local_app_data_dir(), "Logs") == Path.dirname(path())
  end

  defp path do
    {:ok, path} = :gen_event.call(Logger, @backend, :path)
    path
  end

  defp path_for_file_num(file_num) do
    {:ok, path} = :gen_event.call(Logger, @backend, {:path_for_file_num, file_num})
    path
  end

  defp log do
    File.read!(path())
  end

  defp config(opts) do
    :ok = Logger.configure_backend(@backend, opts)
  end

  defp logfile(context) do
    Regex.replace(~r/[^\w]/, Atom.to_string(context.test), "_")
  end

  defp local_app_data_dir do
    [System.get_env("LOCALAPPDATA"), @author, @app, @version]
    |> Path.join()
    |> Path.expand()
  end
end
