use std::collections::HashMap;
use std::io::{self, BufRead, Write};

use base64::Engine;
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use xmtp::{
    AlloySigner, Client, Conversation, ConversationType, CreateGroupOptions, Env, IdentifierKind,
    ListConversationsOptions, ListMessagesOptions, Recipient, SortDirection, content::Content,
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

struct ConversationEntry {
    client_id: String,
    conversation: Conversation,
}

#[derive(Default)]
struct Runtime {
    clients: HashMap<String, Client>,
    conversations: HashMap<String, ConversationEntry>,
    next_client_id: u64,
}

fn main() {
    let stdin = io::stdin();
    let mut stdout = io::stdout();
    let mut runtime = Runtime::default();

    for line in stdin.lock().lines() {
        let line = match line {
            Ok(line) => line,
            Err(error) => {
                write_response(
                    &mut stdout,
                    &Response {
                        id: "unknown",
                        ok: false,
                        result: None,
                        error: Some(format!("stdin read failed: {error}")),
                    },
                );
                continue;
            }
        };

        if line.trim().is_empty() {
            continue;
        }

        let request = match serde_json::from_str::<Request>(&line) {
            Ok(request) => request,
            Err(error) => {
                write_response(
                    &mut stdout,
                    &Response {
                        id: "unknown",
                        ok: false,
                        result: None,
                        error: Some(format!("invalid request json: {error}")),
                    },
                );
                continue;
            }
        };

        let response = match runtime.handle(&request) {
            Ok(value) => Response {
                id: &request.id,
                ok: true,
                result: Some(value),
                error: None,
            },
            Err(error) => Response {
                id: &request.id,
                ok: false,
                result: None,
                error: Some(error),
            },
        };

        write_response(&mut stdout, &response);
    }
}

fn write_response(stdout: &mut io::Stdout, response: &Response<'_>) {
    let _ = serde_json::to_writer(&mut *stdout, response);
    let _ = stdout.write_all(b"\n");
    let _ = stdout.flush();
}

impl Runtime {
    fn handle(&mut self, request: &Request) -> Result<Value, String> {
        match request.op.as_str() {
            "health" => Ok(json!({"status": "ok"})),
            "libxmtp_version" => Ok(json!({"version": xmtp::libxmtp_version().map_err(err)?})),
            "create_client" => self.create_client(&request.params),
            "build_existing_client" => self.build_existing_client(&request.params),
            "close_client" => self.close_client(&request.params),
            "can_message" => self.can_message(&request.params),
            "inbox_id_for" => self.inbox_id_for(&request.params),
            "create_dm" => self.create_dm(&request.params),
            "create_group" => self.create_group(&request.params),
            "get_conversation" => self.get_conversation(&request.params),
            "list_conversations" => self.list_conversations(&request.params),
            "sync_all" => self.sync_all(&request.params),
            "sync_conversation" => self.sync_conversation(&request.params),
            "send_text" => self.send_text(&request.params),
            "list_messages" => self.list_messages(&request.params),
            "count_messages" => self.count_messages(&request.params),
            "members" => self.members(&request.params),
            other => Err(format!("unknown operation: {other}")),
        }
    }

    fn create_client(&mut self, params: &Value) -> Result<Value, String> {
        let private_key = required_string(params, "private_key")?;
        let signer = AlloySigner::from_hex(&private_key).map_err(err)?;
        let client = client_builder(params).build(&signer).map_err(err)?;
        self.store_client(client)
    }

    fn build_existing_client(&mut self, params: &Value) -> Result<Value, String> {
        let address = required_string(params, "address")?;
        let client = client_builder(params)
            .build_existing(&address, IdentifierKind::Ethereum)
            .map_err(err)?;
        self.store_client(client)
    }

    fn store_client(&mut self, client: Client) -> Result<Value, String> {
        self.next_client_id += 1;
        let client_id = format!("client-{}", self.next_client_id);
        let record = client_record(&client_id, &client)?;
        self.clients.insert(client_id, client);
        Ok(record)
    }

    fn close_client(&mut self, params: &Value) -> Result<Value, String> {
        let client_id = required_string(params, "client_id")?;
        self.clients.remove(&client_id);
        self.conversations
            .retain(|_, entry| entry.client_id != client_id);
        Ok(json!({"closed": true}))
    }

    fn can_message(&self, params: &Value) -> Result<Value, String> {
        let client = self.client(params)?;
        let identifiers = required_string_array(params, "addresses")?
            .into_iter()
            .map(|address| xmtp::AccountIdentifier {
                address,
                kind: IdentifierKind::Ethereum,
            })
            .collect::<Vec<_>>();
        let results = client.can_message(&identifiers).map_err(err)?;
        Ok(json!({"results": results}))
    }

    fn inbox_id_for(&self, params: &Value) -> Result<Value, String> {
        let client = self.client(params)?;
        let address = required_string(params, "address")?;
        let inbox_id = client
            .inbox_id_for(&address, IdentifierKind::Ethereum)
            .map_err(err)?;
        Ok(json!({"inbox_id": inbox_id}))
    }

    fn create_dm(&mut self, params: &Value) -> Result<Value, String> {
        let client_id = required_string(params, "client_id")?;
        let client = self
            .clients
            .get(&client_id)
            .ok_or_else(|| format!("client not found: {client_id}"))?;
        let recipient = Recipient::parse(&required_string(params, "recipient")?);
        let conversation = client.dm(&recipient).map_err(err)?;
        self.store_conversation(client_id, conversation)
    }

    fn create_group(&mut self, params: &Value) -> Result<Value, String> {
        let client_id = required_string(params, "client_id")?;
        let client = self
            .clients
            .get(&client_id)
            .ok_or_else(|| format!("client not found: {client_id}"))?;
        let members = required_string_array(params, "members")?
            .into_iter()
            .map(|member| Recipient::parse(&member))
            .collect::<Vec<_>>();
        let options = CreateGroupOptions {
            name: optional_string(params, "name"),
            description: optional_string(params, "description"),
            image_url: optional_string(params, "image_url"),
            app_data: optional_string(params, "app_data"),
            ..Default::default()
        };
        let conversation = client.group(&members, &options).map_err(err)?;
        self.store_conversation(client_id, conversation)
    }

    fn get_conversation(&mut self, params: &Value) -> Result<Value, String> {
        let client_id = required_string(params, "client_id")?;
        let conversation_id = required_string(params, "conversation_id")?;
        let client = self
            .clients
            .get(&client_id)
            .ok_or_else(|| format!("client not found: {client_id}"))?;
        match client.conversation(&conversation_id).map_err(err)? {
            Some(conversation) => self.store_conversation(client_id, conversation),
            None => Ok(json!({"conversation": null})),
        }
    }

    fn list_conversations(&mut self, params: &Value) -> Result<Value, String> {
        let client_id = required_string(params, "client_id")?;
        let client = self
            .clients
            .get(&client_id)
            .ok_or_else(|| format!("client not found: {client_id}"))?;
        let options = ListConversationsOptions {
            conversation_type: optional_conversation_type(params),
            limit: optional_i64(params, "limit").unwrap_or_default(),
            include_duplicate_dms: optional_bool(params, "include_duplicate_dms").unwrap_or(false),
            ..Default::default()
        };
        let conversations = client.list_conversations(&options).map_err(err)?;
        let mut records = Vec::with_capacity(conversations.len());
        for conversation in conversations {
            records.push(self.store_conversation_value(client_id.clone(), conversation)?);
        }
        Ok(json!({"conversations": records}))
    }

    fn sync_all(&self, params: &Value) -> Result<Value, String> {
        let client = self.client(params)?;
        let result = client.sync_all(&[]).map_err(err)?;
        Ok(json!({"synced": result.synced, "eligible": result.eligible}))
    }

    fn sync_conversation(&self, params: &Value) -> Result<Value, String> {
        let conversation = self.conversation(params)?;
        conversation.sync().map_err(err)?;
        Ok(json!({"synced": true}))
    }

    fn send_text(&self, params: &Value) -> Result<Value, String> {
        let conversation = self.conversation(params)?;
        let text = required_string(params, "text")?;
        let message_id = conversation.send_text(&text).map_err(err)?;
        Ok(json!({"message_id": message_id}))
    }

    fn list_messages(&self, params: &Value) -> Result<Value, String> {
        let conversation = self.conversation(params)?;
        let options = ListMessagesOptions {
            limit: optional_i64(params, "limit").unwrap_or_default(),
            direction: optional_sort_direction(params),
            ..Default::default()
        };
        let messages = conversation.list_messages(&options).map_err(err)?;
        let records = messages
            .iter()
            .map(message_record)
            .collect::<Result<Vec<_>, _>>()?;
        Ok(json!({"messages": records}))
    }

    fn count_messages(&self, params: &Value) -> Result<Value, String> {
        let conversation = self.conversation(params)?;
        let count = conversation.count_messages(&ListMessagesOptions::default());
        Ok(json!({"count": count}))
    }

    fn members(&self, params: &Value) -> Result<Value, String> {
        let conversation = self.conversation(params)?;
        let members = conversation.members().map_err(err)?;
        Ok(json!({
            "members": members.into_iter().map(|member| {
                json!({
                    "inbox_id": member.inbox_id,
                    "permission_level": format!("{:?}", member.permission_level),
                    "consent_state": format!("{:?}", member.consent_state),
                    "account_identifiers": member.account_identifiers,
                    "installation_ids": member.installation_ids
                })
            }).collect::<Vec<_>>()
        }))
    }

    fn client(&self, params: &Value) -> Result<&Client, String> {
        let client_id = required_string(params, "client_id")?;
        self.clients
            .get(&client_id)
            .ok_or_else(|| format!("client not found: {client_id}"))
    }

    fn conversation(&self, params: &Value) -> Result<&Conversation, String> {
        let conversation_id = required_string(params, "conversation_id")?;
        self.conversations
            .get(&conversation_id)
            .map(|entry| &entry.conversation)
            .ok_or_else(|| format!("conversation not found: {conversation_id}"))
    }

    fn store_conversation(
        &mut self,
        client_id: String,
        conversation: Conversation,
    ) -> Result<Value, String> {
        let record = self.store_conversation_value(client_id, conversation)?;
        Ok(json!({"conversation": record}))
    }

    fn store_conversation_value(
        &mut self,
        client_id: String,
        conversation: Conversation,
    ) -> Result<Value, String> {
        let record = conversation_record(&conversation)?;
        let id = required_json_string(&record, "id")?;
        self.conversations.insert(
            id,
            ConversationEntry {
                client_id,
                conversation,
            },
        );
        Ok(record)
    }
}

fn client_builder(params: &Value) -> xmtp::ClientBuilder {
    let mut builder = Client::builder().env(parse_env(optional_string(params, "env")));

    if let Some(db_path) = optional_string(params, "db_path") {
        builder = builder.db_path(db_path);
    }

    if let Some(app_version) = optional_string(params, "app_version") {
        builder = builder.app_version(app_version);
    }

    if let Some(api_url) = optional_string(params, "api_url") {
        builder = builder.api_url(api_url);
    }

    if let Some(gateway_host) = optional_string(params, "gateway_host") {
        builder = builder.gateway_host(gateway_host);
    }

    if let Some(nonce) = optional_u64(params, "nonce") {
        builder = builder.nonce(nonce);
    }

    if optional_bool(params, "allow_offline").unwrap_or(false) {
        builder = builder.allow_offline();
    }

    if optional_bool(params, "disable_device_sync").unwrap_or(false) {
        builder = builder.disable_device_sync();
    }

    if let Some(encryption_key_hex) = optional_string(params, "encryption_key_hex") {
        if let Ok(key) = hex::decode(encryption_key_hex.trim_start_matches("0x")) {
            builder = builder.encryption_key(key);
        }
    }

    builder
}

fn client_record(client_id: &str, client: &Client) -> Result<Value, String> {
    let installation_id = client.installation_id().map_err(err)?;
    let installation_bytes = client.installation_id_bytes().map_err(err)?;
    Ok(json!({
        "id": client_id,
        "inbox_id": client.inbox_id().map_err(err)?,
        "installation_id": installation_id,
        "installation_id_bytes": hex::encode(installation_bytes),
        "account_identifier": client.account_identifier().map_err(err)?,
        "app_version": client.app_version().map_err(err)?,
        "libxmtp_version": xmtp::libxmtp_version().map_err(err)?,
        "registered": client.is_registered()
    }))
}

fn conversation_record(conversation: &Conversation) -> Result<Value, String> {
    let metadata = conversation.metadata().ok();
    Ok(json!({
        "id": conversation.id(),
        "created_at_ns": conversation.created_at_ns(),
        "conversation_type": conversation.conversation_type().map(|value| format!("{:?}", value)),
        "name": conversation.name(),
        "description": conversation.description(),
        "image_url": conversation.image_url(),
        "app_data": conversation.app_data(),
        "added_by_inbox_id": conversation.added_by_inbox_id(),
        "dm_peer_inbox_id": conversation.dm_peer_inbox_id(),
        "is_active": conversation.is_active(),
        "creator_inbox_id": metadata.as_ref().map(|value| value.creator_inbox_id.clone()),
        "admins": conversation.admins(),
        "super_admins": conversation.super_admins()
    }))
}

fn message_record(message: &xmtp::Message) -> Result<Value, String> {
    let decoded = message.decode().ok();
    Ok(json!({
        "id": message.id,
        "conversation_id": message.conversation_id,
        "sender_inbox_id": message.sender_inbox_id,
        "sender_installation_id": message.sender_installation_id,
        "sent_at_ns": message.sent_at_ns,
        "inserted_at_ns": message.inserted_at_ns,
        "kind": format!("{:?}", message.kind),
        "delivery_status": format!("{:?}", message.delivery_status),
        "content_type": message.content_type,
        "fallback": message.fallback,
        "expires_at_ns": message.expires_at_ns,
        "num_reactions": message.num_reactions,
        "num_replies": message.num_replies,
        "content": decoded_content(decoded, &message.content)
    }))
}

fn decoded_content(decoded: Option<Content>, raw: &[u8]) -> Value {
    match decoded {
        Some(Content::Text(text)) => json!({"kind": "text", "text": text}),
        Some(Content::Markdown(markdown)) => json!({"kind": "markdown", "markdown": markdown}),
        Some(Content::ReadReceipt) => json!({"kind": "read_receipt"}),
        Some(Content::Unknown { content_type, raw }) => {
            json!({"kind": "unknown", "content_type": content_type, "raw_base64": encode_base64(&raw)})
        }
        _ => json!({"kind": "encoded", "raw_base64": encode_base64(raw)}),
    }
}

fn parse_env(value: Option<String>) -> Env {
    match value.as_deref() {
        Some("local") => Env::Local,
        Some("production") | Some("mainnet") => Env::Production,
        _ => Env::Dev,
    }
}

fn optional_conversation_type(params: &Value) -> Option<ConversationType> {
    match optional_string(params, "conversation_type").as_deref() {
        Some("dm") => Some(ConversationType::Dm),
        Some("group") => Some(ConversationType::Group),
        Some("sync") => Some(ConversationType::Sync),
        Some("oneshot") => Some(ConversationType::Oneshot),
        _ => None,
    }
}

fn optional_sort_direction(params: &Value) -> Option<SortDirection> {
    match optional_string(params, "direction").as_deref() {
        Some("ascending") => Some(SortDirection::Ascending),
        Some("descending") => Some(SortDirection::Descending),
        _ => None,
    }
}

fn required_string(params: &Value, key: &str) -> Result<String, String> {
    params
        .get(key)
        .and_then(Value::as_str)
        .map(ToOwned::to_owned)
        .filter(|value| !value.trim().is_empty())
        .ok_or_else(|| format!("{key} is required"))
}

fn required_json_string(params: &Value, key: &str) -> Result<String, String> {
    required_string(params, key)
}

fn optional_string(params: &Value, key: &str) -> Option<String> {
    params
        .get(key)
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(ToOwned::to_owned)
}

fn required_string_array(params: &Value, key: &str) -> Result<Vec<String>, String> {
    params
        .get(key)
        .and_then(Value::as_array)
        .ok_or_else(|| format!("{key} must be an array"))?
        .iter()
        .map(|value| {
            value
                .as_str()
                .map(ToOwned::to_owned)
                .filter(|item| !item.trim().is_empty())
                .ok_or_else(|| format!("{key} contains an invalid value"))
        })
        .collect()
}

fn optional_bool(params: &Value, key: &str) -> Option<bool> {
    params.get(key).and_then(Value::as_bool)
}

fn optional_i64(params: &Value, key: &str) -> Option<i64> {
    params.get(key).and_then(Value::as_i64)
}

fn optional_u64(params: &Value, key: &str) -> Option<u64> {
    params.get(key).and_then(Value::as_u64)
}

fn encode_base64(bytes: &[u8]) -> String {
    base64::engine::general_purpose::STANDARD.encode(bytes)
}

fn err(error: impl std::fmt::Display) -> String {
    error.to_string()
}
