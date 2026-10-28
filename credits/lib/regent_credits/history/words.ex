defmodule RegentCredits.History.Words do
  @moduledoc """
  The words every Regent site shows for a person's Credits history, so the
  same thing reads the same wherever it is shown.

  `line/1` is the row itself, a few words. The rest name what a page shows
  when a row is opened. A site, purpose or reason this module has no words for
  reads as nothing: a page never prints a code. A site that places holds
  under a new purpose, or gives them back for a new reason, adds its words
  here first.
  """

  @sites %{
    "regents" => "Regents",
    "patchbay" => "Patchbay",
    "keyfleet" => "Keyfleet",
    "autolaunch" => "Autolaunch",
    "techtree" => "Techtree",
    "template" => "Ash Template"
  }

  @purposes %{
    "offer_bid" => "Offer bid",
    "fix" => "Fix",
    "jev_assist" => "Fix",
    "priority_post" => "Priority post",
    "note_pin" => "Note pinned"
  }

  # Patchbay Offers gives a bid back for these.
  @reasons %{
    "outbid" => "Outbid",
    "stale" => "The slot changed before your bid was decided",
    "ineligible" => "The wording could not be shown",
    "cancelled_by_buyout" => "The slot was bought out",
    "next_leader_replaced" => "Outbid",
    "placement_removed" => "The Offer in this slot was removed"
  }

  @chains %{base: "Base"}

  @purchase_failures %{
    "reverted" => "The payment did not go through.",
    "not this purchase" => "That transaction was not this purchase.",
    "not found" => "The payment was not found.",
    "already credited" => "This payment was already added."
  }

  @doc "The few words of a history entry's row."
  @spec line(map()) :: String.t()
  def line(%{kind: :bought}), do: "Bought Credits"
  def line(%{kind: :bought_by_card}), do: "Bought Credits by card"
  def line(%{kind: :card_refunded}), do: "Card payment refunded"
  def line(%{kind: :card_disputed}), do: "Card payment disputed"
  def line(%{kind: :gift}), do: "Gift"
  def line(%{kind: :refund, refund_status: :sent}), do: "Refunded"
  def line(%{kind: :refund}), do: "Refund started"
  def line(%{kind: :set_aside, site: site}), do: at_site("Set aside", "on", site)
  def line(%{kind: :returned, site: site}), do: at_site("Returned", "from", site)
  def line(%{kind: :spent, site: site}), do: at_site("Spent", "on", site)
  def line(%{kind: :received, site: site}), do: at_site("Received", "on", site)

  @doc "A site's name, or `nil`."
  @spec site(String.t() | nil) :: String.t() | nil
  def site(site), do: @sites[site]

  @doc "What a hold was for, or `nil`."
  @spec purpose(String.t() | nil) :: String.t() | nil
  def purpose(purpose), do: @purposes[purpose]

  @doc "Why held Credits came back, or `nil`."
  @spec reason(String.t() | nil) :: String.t() | nil
  def reason(reason), do: @reasons[reason]

  @doc "The chain a purchase was paid on, or `nil`."
  @spec chain(atom() | nil) :: String.t() | nil
  def chain(chain), do: @chains[chain]

  @doc "Why a purchase that added no Credits failed, or `nil`."
  @spec purchase_failure(String.t() | nil) :: String.t() | nil
  def purchase_failure(reason), do: @purchase_failures[reason]

  defp at_site(words, joiner, site) do
    case site(site) do
      nil -> words
      name -> "#{words} #{joiner} #{name}"
    end
  end
end
