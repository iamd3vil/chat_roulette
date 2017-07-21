defmodule ChatRoulette.ChatSup do
  use Supervisor

  def start_link do
    Supervisor.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init([]) do

    :pg2.create("available")
    :pg2.create("connected")

    children = [
      worker(ChatRoulette.ChatWorker, [], restart: :transient),
    ]

    supervise(children, strategy: :simple_one_for_one)
  end

  def start_chat_worker(client) do
    Supervisor.start_child(__MODULE__, [client])
  end
end
