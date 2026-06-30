use std::{
    collections::HashMap,
    io::{self, BufRead, Write},
    str::FromStr,
    sync::Arc,
};

use alloy::{
    primitives::{Address, Bytes, FixedBytes, U256},
    signers::local::PrivateKeySigner as EvmPrivateKeySigner,
};
use eip_1193_provider::provider::{Eip1193Error, Eip1193Provider, RawLog};
use railgun::{
    account::{
        address::RailgunAddress,
        chain::ChainId,
        signer::{spending_key_path, viewing_key_path, PrivateKeySigner, RailgunSigner},
    },
    builder::RailgunBuilder,
    caip::AssetId,
    chain_config::ChainConfig,
    crypto::keys::{HexKey, SpendingKey, ViewingKey},
    indexer::syncer::{ChainedSyncer, RpcSyncer, SubsquidSyncer},
    provider::RailgunProvider,
    transact::TransactionBuilder,
};
use serde::{de::DeserializeOwned, Deserialize, Serialize};
use serde_json::{json, Value};
use userop_kit::{
    bundler::{Bundler, pimlico::PimlicoBundler},
    smart_account::simple_smart_account::{Call, SimpleSmartAccount},
};

#[derive(Debug, Deserialize)]
struct Request {
    id: String,
    op: String,
    #[serde(default)]
    params: Value,
}

#[derive(Debug, Serialize)]
struct Response<'a> {
    id: &'a str,
    ok: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    result: Option<Value>,
    #[serde(skip_serializing_if = "Option::is_none")]
    error: Option<String>,
}

#[derive(Default)]
struct Runtime {
    providers: HashMap<String, RailgunProvider>,
    signers: HashMap<String, Arc<dyn RailgunSigner>>,
    next_provider_id: u64,
    next_signer_id: u64,
}

#[tokio::main]
async fn main() {
    let stdin = io::stdin();
    let mut stdout = io::stdout();
    let mut runtime = Runtime::default();

    for line in stdin.lock().lines() {
        let line = match line {
            Ok(line) => line,
            Err(error) => {
                write_response(&mut stdout, &Response::error("unknown", format!("stdin read failed: {error}")));
                continue;
            }
        };

        if line.trim().is_empty() {
            continue;
        }

        let request = match serde_json::from_str::<Request>(&line) {
            Ok(request) => request,
            Err(error) => {
                write_response(&mut stdout, &Response::error("unknown", format!("invalid request json: {error}")));
                continue;
            }
        };

        let response = match runtime.handle(&request).await {
            Ok(value) => Response {
                id: &request.id,
                ok: true,
                result: Some(value),
                error: None,
            },
            Err(error) => Response::error(&request.id, error),
        };

        write_response(&mut stdout, &response);
    }
}

impl<'a> Response<'a> {
    fn error(id: &'a str, error: String) -> Self {
        Self {
            id,
            ok: false,
            result: None,
            error: Some(error),
        }
    }
}

fn write_response(stdout: &mut io::Stdout, response: &Response<'_>) {
    let _ = serde_json::to_writer(&mut *stdout, response);
    let _ = stdout.write_all(b"\n");
    let _ = stdout.flush();
}

impl Runtime {
    async fn handle(&mut self, request: &Request) -> Result<Value, String> {
        match request.op.as_str() {
            "health" => Ok(json!({"status": "ok"})),
            "chain_config" => self.chain_config(&request.params),
            "chain_config_mainnet" => Ok(json!({"chain": chain_record(&ChainConfig::mainnet())})),
            "chain_config_sepolia" => Ok(json!({"chain": chain_record(&ChainConfig::sepolia())})),
            "erc20" => self.erc20(&request.params),
            "signer_private_key" => self.signer_private_key(&request.params),
            "signer_random" => self.signer_random(&request.params),
            "provider_create" => self.provider_create(&request.params).await,
            "provider_register" => self.provider_register(&request.params).await,
            "provider_sync" => self.provider_sync(&request.params).await,
            "provider_balance" => self.provider_balance(&request.params).await,
            "provider_notes" => self.provider_notes(&request.params).await,
            "shield_build" => self.shield_build(&request.params),
            "transaction_build" => self.transaction_build(&request.params).await,
            "broadcast" => self.broadcast(&request.params).await,
            "spending_key_path" => Ok(json!({"path": spending_key_path(required_u32(&request.params, "index")?)})),
            "viewing_key_path" => Ok(json!({"path": viewing_key_path(required_u32(&request.params, "index")?)})),
            other => Err(format!("unknown operation: {other}")),
        }
    }

    fn chain_config(&self, params: &Value) -> Result<Value, String> {
        let chain_id = required_u64(params, "chain_id")?;
        let chain = ChainConfig::from_chain_id(chain_id)
            .ok_or_else(|| format!("unsupported chain id: {chain_id}"))?;
        Ok(json!({"chain": chain_record(&chain)}))
    }

    fn erc20(&self, params: &Value) -> Result<Value, String> {
        let address = parse_address(&required_string(params, "address")?)?;
        Ok(json!({"asset": asset_record(&AssetId::Erc20(address))}))
    }

    fn signer_private_key(&mut self, params: &Value) -> Result<Value, String> {
        let spending_key = SpendingKey::from_hex(&required_string(params, "spending_key")?)
            .map_err(|error| format!("invalid spending key: {error}"))?;
        let viewing_key = ViewingKey::from_hex(&required_string(params, "viewing_key")?)
            .map_err(|error| format!("invalid viewing key: {error}"))?;
        let chain_id = optional_chain_id(params)?;
        let signer = PrivateKeySigner::new(spending_key, viewing_key, chain_id);
        self.store_signer(signer)
    }

    fn signer_random(&mut self, params: &Value) -> Result<Value, String> {
        let chain_id = optional_chain_id(params)?;
        let signer = PrivateKeySigner::new(rand::random(), rand::random(), chain_id);
        self.store_signer(signer)
    }

    fn store_signer(&mut self, signer: Arc<dyn RailgunSigner>) -> Result<Value, String> {
        self.next_signer_id += 1;
        let id = format!("signer-{}", self.next_signer_id);
        let record = signer_record(&id, signer.as_ref());
        self.signers.insert(id, signer);
        Ok(record)
    }

    async fn provider_create(&mut self, params: &Value) -> Result<Value, String> {
        let chain_id = required_u64(params, "chain_id")?;
        let chain = ChainConfig::from_chain_id(chain_id)
            .ok_or_else(|| format!("unsupported chain id: {chain_id}"))?;
        let rpc_url = required_string(params, "rpc_url")?;
        let rpc_batch_size = optional_u64(params, "rpc_batch_size").unwrap_or(10);
        let poi = optional_bool(params, "poi").unwrap_or(false);

        let rpc_provider = Arc::new(JsonRpcProvider::new(rpc_url));
        let syncer = Arc::new(
            ChainedSyncer::new()
                .then(SubsquidSyncer::new(&chain.subsquid_endpoint))
                .then(RpcSyncer::new(chain.clone(), rpc_provider.clone()).with_batch_size(rpc_batch_size)),
        );

        let mut builder = RailgunBuilder::new(chain.clone(), rpc_provider).with_utxo_syncer(syncer);
        if poi {
            builder = builder.with_poi();
        }

        let provider = builder.build().await.map_err(|error| error.to_string())?;

        self.next_provider_id += 1;
        let id = format!("provider-{}", self.next_provider_id);
        self.providers.insert(id.clone(), provider);
        Ok(json!({"id": id}))
    }

    async fn provider_register(&mut self, params: &Value) -> Result<Value, String> {
        let provider_id = required_string(params, "provider_id")?;
        let signer_id = required_string(params, "signer_id")?;
        let signer = self.signer(&signer_id)?;
        let provider = self.provider_mut(&provider_id)?;
        provider.register(signer).await.map_err(|error| error.to_string())?;
        Ok(json!({"registered": true}))
    }

    async fn provider_sync(&mut self, params: &Value) -> Result<Value, String> {
        let provider_id = required_string(params, "provider_id")?;
        let provider = self.provider_mut(&provider_id)?;
        provider.sync().await.map_err(|error| error.to_string())?;
        Ok(json!({"synced": true}))
    }

    async fn provider_balance(&mut self, params: &Value) -> Result<Value, String> {
        let provider_id = required_string(params, "provider_id")?;
        let address = RailgunAddress::from_str(&required_string(params, "address")?)
            .map_err(|error| format!("invalid railgun address: {error}"))?;
        let provider = self.provider_mut(&provider_id)?;
        let balances = provider.balance(address).await;
        let balances: Vec<Value> = balances
            .into_iter()
            .map(|entry| {
                json!({
                    "asset": asset_record(&entry.asset),
                    "amount": entry.amount.to_string(),
                    "poi_status": entry.poi_status.map(|status| status.to_string()),
                })
            })
            .collect();
        Ok(json!({"balances": balances}))
    }

    async fn provider_notes(&mut self, params: &Value) -> Result<Value, String> {
        let provider_id = required_string(params, "provider_id")?;
        let address = RailgunAddress::from_str(&required_string(params, "address")?)
            .map_err(|error| format!("invalid railgun address: {error}"))?;
        let provider = self.provider_mut(&provider_id)?;
        let notes = provider.notes(address).await;
        let notes: Vec<Value> = notes
            .into_iter()
            .map(|entry| {
                json!({
                    "asset": asset_record(&entry.asset),
                    "amount": entry.amount.to_string(),
                    "poi_status": entry.poi_status.map(|status| status.to_string()),
                    "tree_number": entry.tree_number,
                    "leaf_index": entry.leaf_index,
                    "blinded_commitment": entry.blinded_commitment,
                    "commitment_type": entry.commitment_type,
                    "memo": entry.memo,
                })
            })
            .collect();
        Ok(json!({"notes": notes}))
    }

    fn shield_build(&mut self, params: &Value) -> Result<Value, String> {
        let provider_id = required_string(params, "provider_id")?;
        let provider = self.provider(&provider_id)?;
        let mut builder = provider.shield();

        for op in required_array(params, "operations")? {
            match required_string(op, "type")?.as_str() {
                "shield" => {
                    let recipient = parse_railgun_address(&required_string(op, "recipient")?)?;
                    let asset = parse_asset(required_value(op, "asset")?)?;
                    let amount = required_u128(op, "amount")?;
                    builder = builder.shield(recipient, asset, amount);
                }
                "shield_native" => {
                    let recipient = parse_railgun_address(&required_string(op, "recipient")?)?;
                    let amount = required_u128(op, "amount")?;
                    builder = builder.shield_native(recipient, amount);
                }
                other => return Err(format!("unsupported shield operation: {other}")),
            }
        }

        let mut rng = rand::rng();
        let txs = builder.build(&mut rng).map_err(|error| error.to_string())?;
        Ok(json!({"transactions": txs.into_iter().map(tx_record).collect::<Vec<_>>()}))
    }

    async fn transaction_build(&mut self, params: &Value) -> Result<Value, String> {
        let provider_id = required_string(params, "provider_id")?;
        let operations = required_array(params, "operations")?.to_vec();
        let mut builder = TransactionBuilder::new();
        builder = self.apply_transaction_operations(builder, &operations)?;

        let provider = self.provider_mut(&provider_id)?;
        let mut rng = rand::rng();
        let proved = provider.build(builder, &mut rng).await.map_err(|error| error.to_string())?;
        Ok(tx_record(proved.tx_data))
    }

    async fn broadcast(&mut self, params: &Value) -> Result<Value, String> {
        let provider_id = required_string(params, "provider_id")?;
        let operations = required_array(params, "operations")?.to_vec();
        let bundler_url = required_string(params, "bundler_url")?;
        let smart_account_signer_private_key = required_string(params, "smart_account_signer_private_key")?;
        let chain_id = required_u64(params, "chain_id")?;
        let rpc_url = required_string(params, "rpc_url")?;
        let fee_payer_signer_id = required_string(params, "fee_payer_signer_id")?;
        let fee_token = parse_address(&required_string(params, "fee_token")?)?;
        let native_amount = optional_u128(params, "native_amount").unwrap_or(0);
        let to = optional_string(params, "to");

        let mut builder = TransactionBuilder::new();
        builder = self.apply_transaction_operations(builder, &operations)?;

        let bundler_url = bundler_url
            .parse()
            .map_err(|error| format!("invalid bundler url: {error}"))?;
        let bundler = PimlicoBundler::new(bundler_url);
        let smart_account_signer = EvmPrivateKeySigner::from_str(&smart_account_signer_private_key)
            .map_err(|error| format!("invalid smart account signer: {error}"))?;
        let smart_account_provider = Arc::new(JsonRpcProvider::new(rpc_url));
        let smart_account = SimpleSmartAccount::new(smart_account_signer.address(), chain_id, smart_account_provider);
        let fee_payer = self.signer(&fee_payer_signer_id)?;
        let calls = native_unwrap_calls(fee_token, native_amount, to)?;

        let provider = self.provider_mut(&provider_id)?;
        let mut rng = rand::rng();
        let signable = provider
            .prepare_userop(
                builder,
                &bundler,
                &smart_account,
                fee_payer,
                fee_token,
                calls,
                &mut rng,
            )
            .await
            .map_err(|error| error.to_string())?;
        let signed = signable.sign(&smart_account_signer).await.map_err(|error| error.to_string())?;
        let hash = bundler
            .send_user_operation(&signed)
            .await
            .map_err(|error| error.to_string())?;
        let receipt = bundler
            .wait_for_receipt(hash)
            .await
            .map_err(|error| error.to_string())?;
        Ok(json!({"user_operation_hash": format!("{:?}", hash.0), "success": receipt.success}))
    }

    fn apply_transaction_operations(
        &self,
        mut builder: TransactionBuilder,
        operations: &[Value],
    ) -> Result<TransactionBuilder, String> {
        for op in operations {
            match required_string(op, "type")?.as_str() {
                "transfer" => {
                    let signer = self.signer(&required_string(op, "from_signer_id")?)?;
                    let to = parse_railgun_address(&required_string(op, "to")?)?;
                    let asset = parse_asset(required_value(op, "asset")?)?;
                    let amount = required_u128(op, "amount")?;
                    let memo = optional_string(op, "memo").unwrap_or_default();
                    builder = builder.transfer(signer, to, asset, amount, &memo);
                }
                "unshield" => {
                    let signer = self.signer(&required_string(op, "from_signer_id")?)?;
                    let to = parse_address(&required_string(op, "to")?)?;
                    let asset = parse_asset(required_value(op, "asset")?)?;
                    let amount = required_u128(op, "amount")?;
                    builder = builder
                        .unshield(signer, to, asset, amount)
                        .map_err(|error| error.to_string())?;
                }
                other => return Err(format!("unsupported transaction operation: {other}")),
            }
        }

        Ok(builder)
    }

    fn provider(&self, id: &str) -> Result<&RailgunProvider, String> {
        self.providers
            .get(id)
            .ok_or_else(|| format!("provider not found: {id}"))
    }

    fn provider_mut(&mut self, id: &str) -> Result<&mut RailgunProvider, String> {
        self.providers
            .get_mut(id)
            .ok_or_else(|| format!("provider not found: {id}"))
    }

    fn signer(&self, id: &str) -> Result<Arc<dyn RailgunSigner>, String> {
        self.signers
            .get(id)
            .cloned()
            .ok_or_else(|| format!("signer not found: {id}"))
    }
}

#[derive(Clone)]
struct JsonRpcProvider {
    client: reqwest::Client,
    url: String,
}

#[derive(Debug, Deserialize)]
struct RpcResponse<T> {
    result: Option<T>,
    error: Option<Value>,
}

impl JsonRpcProvider {
    fn new(url: String) -> Self {
        Self {
            client: reqwest::Client::new(),
            url,
        }
    }

    async fn rpc<T: DeserializeOwned>(&self, method: &str, params: Value) -> Result<T, Eip1193Error> {
        let body = json!({
            "jsonrpc": "2.0",
            "id": 1,
            "method": method,
            "params": params,
        });

        let response = self
            .client
            .post(&self.url)
            .json(&body)
            .send()
            .await
            .map_err(|error| Eip1193Error::Rpc(error.to_string()))?;

        let status = response.status();
        let payload: RpcResponse<T> = response
            .json()
            .await
            .map_err(|error| Eip1193Error::Rpc(error.to_string()))?;

        if let Some(error) = payload.error {
            return Err(Eip1193Error::Rpc(format!("{error:?}")));
        }

        payload
            .result
            .ok_or_else(|| Eip1193Error::Rpc(format!("missing rpc result for {method} status={status}")))
    }
}

#[async_trait::async_trait]
impl Eip1193Provider for JsonRpcProvider {
    async fn get_chain_id(&self) -> Result<u64, Eip1193Error> {
        let value: String = self.rpc("eth_chainId", json!([])).await?;
        parse_quantity_u64(&value).map_err(Eip1193Error::Rpc)
    }

    async fn get_block_number(&self) -> Result<u64, Eip1193Error> {
        let value: String = self.rpc("eth_blockNumber", json!([])).await?;
        parse_quantity_u64(&value).map_err(Eip1193Error::Rpc)
    }

    async fn logs(
        &self,
        address: Address,
        event_signature: Option<FixedBytes<32>>,
        from_block: Option<u64>,
        to_block: Option<u64>,
    ) -> Result<Vec<RawLog>, Eip1193Error> {
        let mut filter = json!({"address": address.to_string()});
        if let Some(from_block) = from_block {
            filter["fromBlock"] = json!(quantity(from_block));
        }
        if let Some(to_block) = to_block {
            filter["toBlock"] = json!(quantity(to_block));
        }
        if let Some(event_signature) = event_signature {
            filter["topics"] = json!([format!("{event_signature:?}")]);
        }

        let logs: Vec<Value> = self.rpc("eth_getLogs", json!([filter])).await?;

        logs.into_iter()
            .map(raw_log_from_rpc)
            .collect::<Result<Vec<_>, _>>()
            .map_err(Eip1193Error::Rpc)
    }

    async fn eth_call(&self, to: Address, data: Bytes) -> Result<Bytes, Eip1193Error> {
        let value: String = self
            .rpc(
                "eth_call",
                json!([{"to": to.to_string(), "data": format!("{data:?}")}, "latest"]),
            )
            .await?;
        Bytes::from_str(&value).map_err(|error| Eip1193Error::Decode(error.to_string()))
    }

    async fn estimate_gas(&self, to: Address, data: Bytes, from: Option<Address>) -> Result<u64, Eip1193Error> {
        let mut call = json!({"to": to.to_string(), "data": format!("{data:?}")});
        if let Some(from) = from {
            call["from"] = json!(from.to_string());
        }

        let value: String = self.rpc("eth_estimateGas", json!([call])).await?;
        parse_quantity_u64(&value).map_err(Eip1193Error::Rpc)
    }

    async fn gas_price(&self) -> Result<u128, Eip1193Error> {
        let value: String = self.rpc("eth_gasPrice", json!([])).await?;
        parse_quantity_u128(&value).map_err(Eip1193Error::Rpc)
    }

    async fn transaction_count(&self, address: Address, block: Option<u64>) -> Result<u64, Eip1193Error> {
        let block = block.map(quantity).unwrap_or_else(|| "latest".to_string());
        let value: String = self
            .rpc("eth_getTransactionCount", json!([address.to_string(), block]))
            .await?;
        parse_quantity_u64(&value).map_err(Eip1193Error::Rpc)
    }
}

fn chain_record(chain: &ChainConfig) -> Value {
    json!({
        "id": chain.id,
        "railgun_smart_wallet": chain.railgun_smart_wallet.to_string(),
        "unshield_fee_bps": chain.unshield_fee_bps,
        "relay_adapt_contract": chain.relay_adapt_contract.to_string(),
        "wrapped_base_token": chain.wrapped_base_token.to_string(),
        "deployment_block": chain.deployment_block,
        "poi_start_block": chain.poi_start_block,
        "subsquid_endpoint": chain.subsquid_endpoint,
        "poi_endpoint": chain.poi_endpoint,
        "list_keys": chain.list_keys,
        "privacy_paymaster": chain.privacy_paymaster.map(|address| address.to_string()),
        "railgun_fee_adapter": chain.railgun_fee_adapter.map(|address| address.to_string()),
    })
}

fn signer_record(id: &str, signer: &dyn RailgunSigner) -> Value {
    let chain_id = match signer.chain_id() {
        ChainId::Evm { id } => Some(id),
        ChainId::All => None,
    };

    json!({
        "id": id,
        "address": signer.address().to_string(),
        "chain_id": chain_id,
    })
}

fn tx_record(tx: eip_1193_provider::tx_data::TxData) -> Value {
    json!({
        "to": tx.to.to_string(),
        "data": format!("{:?}", tx.data),
        "value": tx.value.to_string(),
    })
}

fn asset_record(asset: &AssetId) -> Value {
    match asset {
        AssetId::Erc20(address) => json!({"type": "erc20", "contract": address.to_string()}),
        AssetId::Erc721(address, token_id) => {
            json!({"type": "erc721", "contract": address.to_string(), "token_id": token_id.to_string()})
        }
        AssetId::Erc1155(address, token_id) => {
            json!({"type": "erc1155", "contract": address.to_string(), "token_id": token_id.to_string()})
        }
    }
}

fn parse_asset(value: &Value) -> Result<AssetId, String> {
    match required_string(value, "type")?.as_str() {
        "erc20" => Ok(AssetId::Erc20(parse_address(&required_string(value, "contract")?)?)),
        "erc721" => Ok(AssetId::Erc721(
            parse_address(&required_string(value, "contract")?)?,
            parse_u256(&required_string(value, "token_id")?)?,
        )),
        "erc1155" => Ok(AssetId::Erc1155(
            parse_address(&required_string(value, "contract")?)?,
            parse_u256(&required_string(value, "token_id")?)?,
        )),
        other => Err(format!("unsupported asset type: {other}")),
    }
}

fn raw_log_from_rpc(value: Value) -> Result<RawLog, String> {
    let address = parse_address(value.get("address").and_then(Value::as_str).ok_or("log missing address")?)?;
    let data = Bytes::from_str(value.get("data").and_then(Value::as_str).unwrap_or("0x"))
        .map_err(|error| error.to_string())?;
    let topics = value
        .get("topics")
        .and_then(Value::as_array)
        .cloned()
        .unwrap_or_default()
        .into_iter()
        .map(|topic| {
            FixedBytes::<32>::from_str(topic.as_str().ok_or("invalid topic")?)
                .map_err(|error| error.to_string())
        })
        .collect::<Result<Vec<_>, _>>()?;

    let block_number = value
        .get("blockNumber")
        .and_then(Value::as_str)
        .map(parse_quantity_u64)
        .transpose()?;

    let transaction_hash = value
        .get("transactionHash")
        .and_then(Value::as_str)
        .map(|hash| FixedBytes::<32>::from_str(hash).map_err(|error| error.to_string()))
        .transpose()?;

    Ok(RawLog {
        block_number,
        block_timestamp: None,
        transaction_hash,
        address,
        topics,
        data,
    })
}

fn native_unwrap_calls(fee_token: Address, native_amount: u128, to: Option<String>) -> Result<Vec<Call>, String> {
    if native_amount == 0 {
        return Ok(vec![]);
    }

    let _recipient = to.ok_or_else(|| "native unshield recipient is required".to_string())?;
    let mut data = Vec::with_capacity(36);
    data.extend_from_slice(&[0x2e, 0x1a, 0x7d, 0x4d]);
    let mut amount = [0_u8; 32];
    U256::from(native_amount).to_be_bytes_vec().iter().rev().take(32).enumerate().for_each(|(i, byte)| {
        amount[31 - i] = *byte;
    });
    data.extend_from_slice(&amount);

    Ok(vec![Call {
        target: fee_token,
        value: U256::ZERO,
        data: Bytes::from(data),
    }])
}

fn optional_chain_id(params: &Value) -> Result<ChainId, String> {
    match params.get("chain_id") {
        Some(Value::Null) | None => Ok(ChainId::All),
        Some(value) => Ok(ChainId::evm(value.as_u64().ok_or("chain_id must be a number")?)),
    }
}

fn parse_railgun_address(value: &str) -> Result<RailgunAddress, String> {
    RailgunAddress::from_str(value).map_err(|error| error.to_string())
}

fn parse_address(value: &str) -> Result<Address, String> {
    Address::from_str(value).map_err(|error| error.to_string())
}

fn parse_u256(value: &str) -> Result<U256, String> {
    U256::from_str(value).map_err(|error| error.to_string())
}

fn parse_quantity_u64(value: &str) -> Result<u64, String> {
    u64::from_str_radix(value.strip_prefix("0x").unwrap_or(value), 16).map_err(|error| error.to_string())
}

fn parse_quantity_u128(value: &str) -> Result<u128, String> {
    u128::from_str_radix(value.strip_prefix("0x").unwrap_or(value), 16).map_err(|error| error.to_string())
}

fn quantity(value: u64) -> String {
    format!("0x{value:x}")
}

fn required_value<'a>(params: &'a Value, key: &str) -> Result<&'a Value, String> {
    params.get(key).ok_or_else(|| format!("missing required field: {key}"))
}

fn required_string(params: &Value, key: &str) -> Result<String, String> {
    params
        .get(key)
        .and_then(Value::as_str)
        .map(ToString::to_string)
        .ok_or_else(|| format!("missing required string: {key}"))
}

fn optional_string(params: &Value, key: &str) -> Option<String> {
    params.get(key).and_then(Value::as_str).map(ToString::to_string)
}

fn required_array<'a>(params: &'a Value, key: &str) -> Result<&'a [Value], String> {
    params
        .get(key)
        .and_then(Value::as_array)
        .map(Vec::as_slice)
        .ok_or_else(|| format!("missing required array: {key}"))
}

fn required_u64(params: &Value, key: &str) -> Result<u64, String> {
    params
        .get(key)
        .and_then(Value::as_u64)
        .ok_or_else(|| format!("missing required number: {key}"))
}

fn optional_u64(params: &Value, key: &str) -> Option<u64> {
    params.get(key).and_then(Value::as_u64)
}

fn required_u32(params: &Value, key: &str) -> Result<u32, String> {
    let value = required_u64(params, key)?;
    u32::try_from(value).map_err(|error| error.to_string())
}

fn required_u128(params: &Value, key: &str) -> Result<u128, String> {
    match params.get(key) {
        Some(Value::String(value)) => value.parse::<u128>().map_err(|error| error.to_string()),
        Some(Value::Number(value)) => value.as_u64().map(u128::from).ok_or_else(|| format!("{key} must be non-negative")),
        _ => Err(format!("missing required integer: {key}")),
    }
}

fn optional_u128(params: &Value, key: &str) -> Option<u128> {
    params.get(key).and_then(|value| match value {
        Value::String(value) => value.parse::<u128>().ok(),
        Value::Number(value) => value.as_u64().map(u128::from),
        _ => None,
    })
}

fn optional_bool(params: &Value, key: &str) -> Option<bool> {
    params.get(key).and_then(Value::as_bool)
}
