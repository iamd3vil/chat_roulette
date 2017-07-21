defmodule ChatRoulette do
  use Application

  # See http://elixir-lang.org/docs/stable/elixir/Application.html
  # for more information on OTP Applications
  def start(_type, _args) do
    import Supervisor.Spec, warn: false

    tcp_port = System.get_env("TCP_PORT") |> String.to_integer()

    # Define workers and child supervisors to be supervised
    children = [
      # Starts a worker by calling: ChatRoulette.Worker.start_link(arg1, arg2, arg3)
      # worker(ChatRoulette.Worker, [arg1, arg2, arg3]),
      # supervisor(Task.Supervisor, [[name: ChatRoulette.TaskSup]]),
      supervisor(ChatRoulette.ChatSup, []),
      worker(Task, [ChatRoulette.TcpServer, :accept, [tcp_port]])
    ]

    # See http://elixir-lang.org/docs/stable/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: ChatRoulette.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
