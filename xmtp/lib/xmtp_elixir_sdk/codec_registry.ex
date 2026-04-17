defmodule XmtpElixirSdk.CodecRegistry do
  @moduledoc """
  Registry of custom content codecs keyed by canonical content type.
  """

  alias XmtpElixirSdk.Content
  alias XmtpElixirSdk.Error
  alias XmtpElixirSdk.Types.ContentTypeId

  defstruct codecs: %{}

  @type codec_module :: module()
  @type t :: %__MODULE__{codecs: %{optional(String.t()) => codec_module()}}

  @spec new([codec_module()]) :: t()
  def new(codecs \\ []) do
    Enum.reduce(codecs, %__MODULE__{}, &register(&2, &1))
  end

  @spec register(t(), codec_module()) :: t()
  def register(%__MODULE__{} = registry, codec) when is_atom(codec) do
    content_type = codec.content_type()
    key = Content.content_type_to_string(content_type)
    %{registry | codecs: Map.put(registry.codecs, key, codec)}
  end

  @spec get_codec(t(), ContentTypeId.t() | String.t()) :: codec_module() | nil
  def get_codec(%__MODULE__{codecs: codecs}, %ContentTypeId{} = content_type) do
    Map.get(codecs, Content.content_type_to_string(content_type))
  end

  def get_codec(%__MODULE__{codecs: codecs}, content_type) when is_binary(content_type) do
    Map.get(codecs, content_type)
  end

  @spec encode(t(), codec_module(), term()) :: {:ok, Content.Unknown.t()} | {:error, Error.t()}
  def encode(%__MODULE__{} = registry, codec, value) when is_atom(codec) do
    content_type = codec.content_type()

    with ^codec <- get_codec(registry, content_type),
         {:ok, raw} <- call_codec(codec, :encode, [value]) do
      {:ok,
       %Content.Unknown{
         content_type: Content.content_type_to_string(content_type),
         raw: raw
       }}
    else
      nil ->
        {:error,
         Error.invalid_argument("codec is not registered", %{
           content_type: Content.content_type_to_string(content_type)
         })}

      {:error, %Error{} = error} ->
        {:error, error}
    end
  end

  @spec decode(t(), Content.Unknown.t() | term()) ::
          {:ok, term()} | {:error, :missing_codec | Error.t()}
  def decode(%__MODULE__{} = registry, %Content.Unknown{content_type: content_type, raw: raw}) do
    case get_codec(registry, content_type) do
      nil -> {:error, :missing_codec}
      codec -> call_codec(codec, :decode, [raw])
    end
  end

  def decode(_registry, other),
    do: {:error, Error.invalid_argument("expected custom content", %{content: other})}

  @spec call_codec(codec_module(), :encode | :decode, [term()]) ::
          {:ok, term()} | {:error, Error.t()}
  defp call_codec(codec, fun, args) do
    apply(codec, fun, args)
  rescue
    error in UndefinedFunctionError ->
      {:error,
       Error.invalid_argument("codec is missing a required callback", %{
         codec: inspect(codec),
         callback: fun,
         error: Exception.message(error)
       })}

    error ->
      {:error,
       Error.invalid_argument("codec #{fun} failed", %{
         codec: inspect(codec),
         error: Exception.message(error)
       })}
  end
end
