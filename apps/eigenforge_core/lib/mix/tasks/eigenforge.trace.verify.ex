defmodule Mix.Tasks.Eigenforge.Trace.Verify do
  use Mix.Task

  @shortdoc "Verify an Eigenforge simulator trace"

  @impl Mix.Task
  def run(args) do
    {opts, _argv, _invalid} = OptionParser.parse(args, strict: [trace: :string])
    trace = Keyword.fetch!(opts, :trace)

    Mix.Task.run("app.start")

    case Eigenforge.Trace.verify_file(trace) do
      :ok -> Mix.shell().info("trace verified: #{trace}")
      {:error, reason} -> Mix.raise("trace verification failed: #{inspect(reason)}")
    end
  end
end
