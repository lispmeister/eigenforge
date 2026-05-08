defmodule Mix.Tasks.Eigenforge.Trace.Run do
  use Mix.Task

  @shortdoc "Run an Eigenforge simulator trace"

  @impl Mix.Task
  def run(args) do
    {opts, _argv, _invalid} = OptionParser.parse(args, strict: [fixture: :string, out: :string])
    fixture = Keyword.fetch!(opts, :fixture)

    Mix.Task.run("app.start")

    case Eigenforge.Trace.run_file(fixture) do
      {:ok, trace} ->
        json = Eigenforge.Contracts.canonical_json(trace)

        case Keyword.get(opts, :out) do
          nil ->
            Mix.shell().info(json)

          path ->
            File.mkdir_p!(Path.dirname(path))
            File.write!(path, json <> "\n")
            Mix.shell().info("wrote #{path}")
        end

      {:error, reason} ->
        Mix.raise("trace run failed: #{inspect(reason)}")
    end
  end
end
