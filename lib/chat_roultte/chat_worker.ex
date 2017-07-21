defmodule ChatRoulette.ChatWorker do
  use GenServer
  require Logger

  def start_link(client) do
    GenServer.start_link(__MODULE__, client, [])
  end

  def init(client) do
    :gen_tcp.send(client, "Hi. Welcome to Chat Roulette. We are going to connect you to a stranger. For now please enter your name:\r\n")
    {:ok, name} = recv_name(client) # Get the name of the client.
    Logger.debug "Client connected. Name: #{inspect name}"
    connected_proc =
      case :pg2.get_members("available") do
        [] ->
          :pg2.join("available", self())
          :gen_tcp.send(client, "Hey #{name}. Waiting for someone to join\r\n")
          nil
        members ->
          member = Enum.random(members)
          GenServer.call(member, {:connect, self()})
          :gen_tcp.send(client, "Hey #{name}. Found someone. Say hi\r\n")
          member
      end
    :inet.setopts(client, active: :once)
    {:ok, %{socket: client, name: name, connected_proc: connected_proc}}
  end

  # If we get data when we are not connected, just send a wait message.
  def handle_info({:tcp, socket, _data}, %{connected_proc: nil, socket: client} = state) do
    :gen_tcp.send(client, "You are not connected to anyone. Have patience :)")
    :inet.setopts(socket, active: :once)
    {:noreply, state}
  end

  # If the client just presses `Enter`, ignore it.
  def handle_info({:tcp, socket, "\n"}, %{connected_proc: pid} = state)
                  when is_pid(pid) do
    :inet.setopts(socket, active: :once)
    {:noreply, state}
  end

  # When we are connected send the connected process the data we got.
  def handle_info({:tcp, socket, line}, %{connected_proc: pid, socket: _client, name: name} = state) do
    Logger.debug "Received new message from #{name}"
    GenServer.cast(pid, {:new_message, "#{name}: #{line}"})
    :inet.setopts(socket, active: :once)
    {:noreply, state}
  end

  def handle_info({:tcp_closed, _}, state) do
    {:stop, :normal, state}
  end

  # When the process dies, send a message to connected_proc to disconnect.
  def terminate(:normal, %{connected_proc: pid, socket: _}) do
    GenServer.cast(pid, :disconnect)
    :ok
  end

  # Got connect request.
  def handle_call({:connect, pid}, _from, %{name: name, socket: client} = state) do
    Logger.debug "Got connect request from pid"
    :pg2.leave("available", self())
    :pg2.join("connected", self())
    :gen_tcp.send(client, "Hey #{name}. Found someone say hi\r\n")
    {:reply, :ok, %{ state | connected_proc: pid, name: name}}
  end

  def handle_cast(:disconnect, %{socket: client, name: name}) do
    :pg2.leave("connected", self())
    :pg2.join("available", self())
    :gen_tcp.send(client, "Your partner left. Waiting for someone else now\r\n")
    {:noreply, %{socket: client, connected_proc: nil, name: name}}
  end

  def handle_cast({:new_message, msg}, %{socket: client, connected_proc: _pid} = state) do
    :gen_tcp.send(client, msg)
    {:noreply, state}
  end

  defp recv_name(socket) do
    case :gen_tcp.recv(socket, 0) do
      {:ok, "\n"} ->
        :gen_tcp.send(socket, "Eh? I don't think that's your name.. :(\r\n")
        recv_name(socket)
      {:ok, name} ->
        {:ok, String.trim(name)}
    end
  end
end
