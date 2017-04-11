defmodule ConnectFour.Game do
  @moduledoc """
  Module to conduct a game.
  """
  use GenServer
  require Logger
  alias ConnectFour.Matrix
  @board_columns 7
  @board_rows 6

  # Startup and Initialization
  def start_link(opts \\ []) do
    #TODO Support multiple game processes running simulteaneously for the same players
    opts_map = get_player_opts_map(opts)

    case opts_map |> Map.values |> Enum.all?(&(&1 != nil)) do
      true ->
        name = get_game_process_name(opts_map.player_1, opts_map.player_2)
        GenServer.start_link(__MODULE__, opts, name: name)
      _ ->
        Logger.warn("#{__MODULE__} error: both player names required to start game")
    end
  end

  def init(opts) do
    Logger.debug("#{__MODULE__} starting...")
    board = generate_default_board()

    state = %{
      board: board,
      status: nil,
      winner: nil
    } |> Map.merge(get_player_opts_map(opts))

    {:ok, state}
  end

  #API
  @doc """
  Drops a disc into an available slot in the specified column.

  The specified column should be a number between 1 and 7
  """
  def drop_disc(pid, player, column_number) do
    internal_column_number = column_number-1
    GenServer.cast(pid, {:drop_disc, [player, internal_column_number]})
  end

  @doc """
  Resets the game board to its default state.
  """
  def reset_board(pid) do
    GenServer.cast(pid, {:reset_game_board})
  end

  @doc """
  Gets the current status of the game.
  """
  def get_game_status(pid) do
    GenServer.call(pid, {:get_game_status})
  end

  def handle_cast({:drop_disc, [player, column_number]}, state) do
    Logger.debug("handle_cast drop_disc player=#{player}, column=#{column_number}")
    color = case player do
      :player_1 -> state.player_1_color
      :player_2 -> state.player_2_color
    end

    column = state.board |> Enum.at(column_number) |> elem(1)

    available_slots = column |> Enum.filter(fn{k, v} -> v == nil end) |> Enum.into(%{})
    board = case available_slots |> Enum.count do
      0 ->
        Logger.warn("No available slots in column #{column_number}")
        state.board
      _ ->
        slot = available_slots |> Map.keys |> List.last
        put_in(state.board[column_number][slot], color) |> Map.get(:board)
    end

    Matrix.to_list(board) |> Matrix.print

    #TODO determine/update game state i.e. win/lose/tie etc.
    GenServer.cast(self(), {:update_status, [color, board, player]})

    {:noreply, %{state | board: board}}
  end

  def handle_cast({:reset_game_board}, state) do
    board = generate_default_board()

    {:noreply, %{state | board: board}}
  end

  def handle_cast({:update_status, [color, board, player]}, state) do
    player_name = case player do
      :player_1 -> state.player_1
      :player_2 -> state.player_2
    end

    {status, winner} = case four_connected?(color, board) do
      true -> {:complete, player_name}
      false -> {nil, nil}
    end

    {:noreply, %{state | status: status, winner: winner}}
  end

  def handle_call({:get_game_status}, from, state) do
    reply = %{status: state.status, winner: state.winner}
    {:reply, reply, state}
  end

  #Private Helpers
  defp generate_default_board() do
    board_columns = for n <- 0..(@board_columns-1), do: %{n => generate_default_board_rows()}
    board_columns |> Enum.reduce(fn(x, acc) -> Map.merge(x, acc) end)
  end

  defp generate_default_board_rows() do
    rows = for n <- 0..(@board_rows-1), do: %{n => nil}
    rows |> Enum.reduce(fn(x, acc) -> Map.merge(x, acc) end)
  end

  defp get_player_opts_map(opts) do
    player_1 = opts[:player_1]
    player_2 = opts[:player_2]
    player_1_color = opts[:player_1_color]
    player_2_color = opts[:player_2_color]

    game_opts = [player_1: player_1, player_2: player_2, player_1_color: player_1_color, player_2_color: player_2_color]
    game_opts |> Enum.into(%{})
  end

  defp get_game_process_name(player_1, player_2) do
    "#{__MODULE__}-#{player_1}v#{player_2}" |> String.to_atom
  end

  defp four_connected?(color, board) do
    cond do
      !horizontal_win?(color, board) -> false
      true -> true
    end
  end

  defp horizontal_win?(color, board) do
    results = 0..@board_columns-1 |> Enum.to_list |> Enum.map(fn(column) ->
      win = board[column]
      |> Map.values
      |> Enum.filter(&(&1 == color))
      |> Enum.count == 4
    end)

    results |> Enum.any?(&(&1))
  end

  defp check_rows(column, color, board) do
    results = 0..@board_rows-3 |> Enum.to_list |> Enum.map(fn(row) ->
      board[column][row]
    end)
    Logger.warn("check_rows #{inspect results}")

    results |> Enum.all?(&(&1 == color))
  end
end
