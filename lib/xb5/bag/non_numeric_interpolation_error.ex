defmodule Xb5.Bag.NonNumericInterpolationError do
  @moduledoc """
  Raised by `Xb5.Bag.percentile/3` when linear interpolation is required but one of the
  bracketing elements is not a number.

  Percentile interpolation computes a weighted average between two adjacent elements. If
  either element is not numeric (e.g. an atom or a string), the result would be
  meaningless, so this error is raised instead.

  Fields:

    * `:value` — the non-numeric element that caused the failure.
    * `:bracket` — the full `{:between, lo, hi, t}` bracket in which the failure occurred.

  """

  defexception [:value, :bracket, :message]

  @impl true
  def exception(opts) do
    value = Keyword.fetch!(opts, :value)
    bracket = Keyword.fetch!(opts, :bracket)

    message =
      "percentile interpolation requires numeric elements, " <>
        "got non-numeric value #{inspect(value)} in bracket #{inspect(bracket)}"

    %__MODULE__{value: value, bracket: bracket, message: message}
  end
end
