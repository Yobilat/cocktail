defmodule Cocktail.Builder.ICalendar do
  @moduledoc """
  Build iCalendar format strings from schedules.

  TODO: write long description
  """

  alias Cocktail.{Rule, Schedule}
  alias Cocktail.Validation.{Interval, Day, HourOfDay}

  @time_format_string "{YYYY}{0M}{0D}T{h24}{m}{s}"

  @doc ~S"""
  Builds an iCalendar format string represenation of a `t:Cocktail.Schedule.t/0`.

  ## Examples

      iex> alias Cocktail.Schedule
      ...> start_time = Timex.to_datetime(~N[2017-01-01 06:00:00], "America/Los_Angeles")
      ...> schedule = Schedule.new(start_time)
      ...> schedule = Schedule.add_recurrence_rule(schedule, :daily, interval: 2, hours: [10, 12])
      ...> build(schedule)
      "DTSTART;TZID=America/Los_Angeles:20170101T060000\nRRULE:FREQ=DAILY;INTERVAL=2;BYHOUR=10,12"

      iex> alias Cocktail.Schedule
      ...> schedule = Schedule.new(~N[2017-01-01 06:00:00])
      ...> schedule = Schedule.add_recurrence_rule(schedule, :daily, until: ~N[2017-01-31 11:59:59])
      ...> build(schedule)
      "DTSTART:20170101T060000\nRRULE:FREQ=DAILY;UNTIL=20170131T115959"

      iex> alias Cocktail.Schedule
      ...> schedule = Schedule.new(~N[2017-01-01 06:00:00])
      ...> schedule = Schedule.add_recurrence_rule(schedule, :daily, count: 3)
      ...> build(schedule)
      "DTSTART:20170101T060000\nRRULE:FREQ=DAILY;COUNT=3"
  """
  def build(schedule) do
    rules =
      schedule.recurrence_rules
      |> Enum.map(&build_rule/1)

    start_time = build_start_time(schedule.start_time)
    end_time = build_end_time(schedule)

    [start_time] ++ rules ++ [end_time]
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n")
  end

  defp build_time(%DateTime{} = time, prefix) do
    timezone = time.time_zone
    time_string = Timex.format!(time, @time_format_string)
    "#{prefix};TZID=#{timezone}:#{time_string}"
  end
  defp build_time(%NaiveDateTime{} = time, prefix) do
    time_string = Timex.format!(time, @time_format_string)
    "#{prefix}:#{time_string}"
  end

  defp build_start_time(time), do: build_time(time, "DTSTART")

  defp build_end_time(%Schedule{duration: nil}), do: nil
  defp build_end_time(%Schedule{start_time: start_time, duration: duration}) do
    start_time
    |> Timex.shift(seconds: duration)
    |> build_time("DTEND")
  end

  defp build_utc_time(%NaiveDateTime{} = time), do: Timex.format!(time, @time_format_string)
  defp build_utc_time(%DateTime{} = time) do
    time
    |> Timex.to_datetime("UTC")
    |> Timex.format!(@time_format_string <> "Z")
  end

  defp build_rule(%Rule{validations: validations_map, until: until, count: count}) do
    parts =
      for key <- [:interval, :day, :hour_of_day],
          validations = validations_map[key],
          is_list(validations)
      do
        build_validation_part(key, validations)
      end

    parts = parts ++ build_until(until) ++ build_count(count)

    "RRULE:" <> (parts |> List.flatten |> Enum.join(";"))
  end

  defp build_validation_part(:interval, [%Interval{interval: interval, type: type}]), do: build_interval(type, interval)
  defp build_validation_part(:day, days), do: days |> Enum.map(fn(%Day{day: day}) -> day end) |> build_days()
  defp build_validation_part(:hour_of_day, hours), do: hours |> Enum.map(fn(%HourOfDay{hour: hour}) -> hour end) |> build_hours()

  defp build_until(nil), do: []
  defp build_until(time), do: ["UNTIL=" <> build_utc_time(time)]

  defp build_count(nil), do: []
  defp build_count(count), do: ["COUNT=#{count}"]

  # intervals

  defp build_interval(type, 1), do: "FREQ=" <> build_frequency(type)
  defp build_interval(type, n), do: ["FREQ=" <> build_frequency(type), "INTERVAL=#{n}"]

  defp build_frequency(type), do: type |> Atom.to_string |> String.upcase

  # "day" validation

  defp build_days(days) do
    days_list =
      days
      |> Enum.sort
      |> Enum.map(&by_day/1)
      |> Enum.join(",")

    "BYDAY=#{days_list}"
  end

  defp by_day(0), do: "SU"
  defp by_day(1), do: "MO"
  defp by_day(2), do: "TU"
  defp by_day(3), do: "WE"
  defp by_day(4), do: "TH"
  defp by_day(5), do: "FR"
  defp by_day(6), do: "SA"

  # "hour of day" validation

  defp build_hours(hours) do
    hours_list =
      hours
      |> Enum.sort
      |> Enum.join(",")

    "BYHOUR=#{hours_list}"
  end
end