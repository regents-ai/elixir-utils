defmodule XmtpElixirSdk.MetadataTest do
  use ExUnit.Case, async: true

  alias XmtpElixirSdk.Content
  alias XmtpElixirSdk.Metadata
  alias XmtpElixirSdk.Types

  test "metadata helpers round-trip field names and detect changes" do
    assert Metadata.field_name(:image_url) == "group_image_url_square"
    assert {:ok, :image_url} = Metadata.field_from_name("group_image_url_square")

    updated = %Content.GroupUpdated{
      metadata_field_changes: [
        %Types.MetadataFieldChange{
          field_name: "group_image_url_square",
          old_value: "",
          new_value: "https://example.com/one.png"
        },
        %Types.MetadataFieldChange{
          field_name: "app_data",
          old_value: "",
          new_value: "payload"
        }
      ]
    }

    assert Metadata.changed_fields(updated) == [:image_url, :app_data]
    assert Metadata.field_changed?(updated, :image_url)
    refute Metadata.field_changed?(updated, :description)
  end
end
